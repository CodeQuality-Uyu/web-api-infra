# Onboarding

## AWS accounts & authentication
Each client-env declares the AWS account it deploys into:

```hcl
client = "sayer", environment = "prod", aws_account_id = "111111111111"
# aws_role_name = "custom-role"   # optional; defaults to var.tfc_role_name ("tfc-deploy")
```

That single value drives two things:
- **Auth (which account):** the factory sets `TFC_AWS_PROVIDER_AUTH=true` and
  `TFC_AWS_RUN_ROLE_ARN=arn:aws:iam::<account>:role/<role>` as **env** variables on every
  workspace (foundation, service, frontend). HCP dynamic provider credentials assume that role
  via OIDC — **no long-lived AWS keys anywhere**. Neither value is a secret, so both live in git.
- **Guardrail (only that account):** each stack passes it to `allowed_account_ids`, so a run
  whose credentials belong to a different account **fails the plan** instead of creating the
  client's infrastructure in the wrong account.

**Prerequisite, once per AWS account:** create the IAM role (default name `tfc-deploy`) trusting
HCP's OIDC provider (`app.terraform.io`), scoped to your org/workspaces, with the permissions the
stacks need. Without it the runs can't authenticate.

## New client
Add a client block to `factory/clients.auto.tfvars` with `client`, `environment`, `zone_name`,
`aws_account_id`, and two lists:

- **`backends`** — the APIs. Each is `{ app, version, connections, subdomain, github_repo,
  settings?, secret_settings?, extra_cors_origins? }`, where `connections` is a list of
  `{ key, db_name, migrate?, source? }`.
- **`frontends`** — the SPAs. Each is `{ name, version, bucket_name?, serve_on_zone_root?, domain?, calls? }`,
  where `calls` is a list of `{ backend, source? }`.

Anything pointing at **another client-env** (a shared db, a backend the SPA calls) uses
`source = { client = "...", environment = "..." }` — a different AWS account is fine.

Applying the factory creates the `{client}-{env}-foundation` workspace, one
`{client}-{app}-{env}-service` per backend and one `{client}-{name}-{env}-frontend` per frontend,
wires their variables, and adds run-triggers so they apply after the foundation.

Then, once: apply the foundation (creates the VPC, zone, and one ECR repo per app), copy its
`name_servers` into the parent zone (automatic when DNS delegation is configured — see
`docs/arquitectura/02-dns.md`; otherwise add the NS records by hand), and push the first
image (`{client}-{app}-{env}:{version}`) to ECR — App Runner needs it before the service applies.

## New app for an existing client
Add another entry to that client's `backends` list and re-apply the factory. Re-apply the
foundation too (adds that app's ECR repo), push its first image, then the new service workspace.

## Releasing a new version
Push an immutable `{client}-{app}-{env}:{version}` image to ECR, bump that app's `version`
in `clients.auto.tfvars`, apply the factory (updates the service workspace's `image_version`),
then run the service workspace. The plan promotes App Runner's image and its `APP_VERSION` env
var, and re-stamps `APP_VERSION_DATE` to now (a `time_static` keyed on the version) — so
`/health` reflects the new version + release date. (`auto_deploy` is off; Terraform owns which
version runs.)

## Databases (how & when they're created)
One RDS instance per client-env lives in the **foundation**. Apps can connect to **more than
one** database: each app lists `connections = [{ key, db_name, migrate }]`, and foundation
creates the **distinct set** of every `db_name` referenced (a db shared by several backends is
created once). Names are explicit; each becomes an SSM SecureString **connection string**
(`...;Database=<db_name>`, master creds). App Runner injects one `ConnectionStrings__<key>` per
connection. Creating the RDS instance does **not** create the databases — only the default
`postgres` db exists at that point.

The **migration job creates the app's own database(s) on first run.** Connections with
`migrate = true` are the app's own dbs (usually one; `authprovider` owns two: AuthProvider +
IdentityProvider). The service hands the migration CodeBuild `DB_HOST`, `DB_PORT`, and
`MIGRATE_CONNECTIONS` (a JSON map `db_name -> SSM param`); the buildspec loops and runs
`dotnet ef database update` per db (one EF Core context each), which **CREATEs the database if
missing** (master credential). So the timeline is:

```
foundation apply   → RDS instance + connection strings (db not created yet)
service apply       → App Runner + migration runner
first migrate run   → database created + schema applied   ← db exists here
```

Ordering note: App Runner may report unhealthy in the window between `service apply` and the
first migrate (its db doesn't exist yet); it recovers on the next health check once migrate has
run. For a clean first bring-up, trigger the migrate workflow right after the service applies.

## Shared databases across clients (cross-account)
A connection can point at a database owned by **another** client-env — even in another AWS
account — by setting `source` to that client-env's foundation workspace, e.g.:
`{ key = "Admin", db_name = "EColorsAdminProd", source = { client = "ecolors", environment = "prod" } }`.

How it works (see `docs/adr/0007`):
- The **provider** client-env (ecolors) exposes its RDS **publicly** (`db_public`, set by the
  factory when someone references its dbs) and allowlists each **consumer**'s NAT egress IP —
  read from the consumer foundations via HCP remote state. SSL is enforced.
- The **consumer** service reads the provider foundation's connection string (a `sensitive`
  remote-state output — works cross-account because remote state is org-level, not AWS-level),
  re-stores it in its **own** SSM SecureString, and injects it as `ConnectionStrings__<key>`.
- Shared dbs are **not** migrated by the consumer (no `migrate = true`) — the owning app migrates them.

First-time ordering: apply the **consumer foundations first** (their NAT EIP must exist), then
the **provider foundation** (it allowlists those IPs and exposes the creds), then the services.
The factory adds run-triggers so a consumer-foundation change re-runs the provider, and a
provider change (e.g. password rotation) re-runs the consumer services.

## App config & secrets (env vars)
.NET reads `appsettings.json`, then env vars override matching keys using the `Key__Child`
convention. Both flow from Terraform workspace variables into App Runner:

- **Plaintext config** → `settings` map per app in `clients.auto.tfvars` (git). The factory writes
  it to the service workspace's `runtime_env`; App Runner injects it as
  `runtime_environment_variables`. Example: `{ "Serilog__MinimumLevel__Default" = "Information" }`.
- **Secrets** → declare only the **names** in `secret_settings` per app (git). Put the **values**
  in a **sensitive** `secret_values` map variable on the service workspace (TFC UI, never git).
  Terraform stores each in an SSM SecureString (`/app/{env}/secrets/{client}-{app}-{env}/{key}`)
  and App Runner injects it as `runtime_environment_secrets`, decrypted at start.

Notes: `APP_VERSION` / `APP_VERSION_DATE` are injected automatically and win over `settings`.
Don't put the same key in both `settings` and `secret_settings`. A name in `secret_settings`
with no matching `secret_values` entry fails the plan (intended — provision the value first).

## Frontends (SPAs)
A client-env can host **zero, one or many** SPAs. Add a `frontends` list and apply the factory —
each entry stamps a `{client}-{name}-{env}-frontend` workspace (working dir `stacks/frontend`):

```hcl
frontends = [
  # Domain is DERIVED as "<name>.<zone_name>" -> admin.prod.ecolors.app
  { name        = "admin"
    version     = "1.0.0"
    bucket_name = "ecolors-admin-prod-web"               # optional; default "{client}-{name}-{env}-web"
    calls       = [{ backend = "admin-webapi" }, { backend = "authprovider-webapi" }]
    # serve_on_zone_root        = true                   # serve on the zone itself instead
    # domain                    = "app.example.com"      # fully custom; wins over serve_on_zone_root
    # www_redirect              = true                   # answer on www.<domain>, 301 to the zone root
    # subject_alternative_names = ["legacy.example.com"] # extra names that SERVE the same content
  },
]
```

**Domain convention:** frontend at `<name>.<zone>`, backend at `<app>.api.<zone>`. So
`admin.prod.ecolors.app` is the SPA and `admin.api.prod.ecolors.app` is the API it calls. Set
`serve_on_zone_root = true` on the one frontend that should answer on the zone itself (at most one
per client-env) — that's the case for single-SPA licensees like `sayer.ecolors.app`.

### `calls` drives CORS (do not leave it incomplete)
`calls` lists the backends the SPA hits **from the browser** — including the identity provider,
since login is browser-side. Each entry is `{ backend, source? }`; `source` is the client-env
that owns the backend (another AWS account is fine), omitted when it's local:

```hcl
calls = [
  { backend = "webapi" },                                                             # this client-env
  { backend = "authprovider-webapi", source = { client = "ecolors", environment = "prod" } },
]
```

The factory **inverts** this relationship and injects each API's allowed origins as
`Cors__AllowedOrigins__0`, `__1`, … (configurable with `var.cors_settings_key`). So
`authprovider-webapi` in ecolors-prod automatically allows the admin, authprovider, sayer and
ulbrika frontends — across three AWS accounts — with no hand-written CORS anywhere.

Consequences worth knowing:
- **Adding a frontend updates CORS by itself.** Forgetting an entry here is what breaks login in
  production, so the factory validates that every referenced app actually exists.
- Derived origins **win** over anything you set manually in `settings` for that key.
- For extra origins that don't come from a frontend (a local dev server, say), use
  `extra_cors_origins` on the **backend**: `extra_cors_origins = ["http://localhost:5173"]`.
- `www_redirect` domains are **not** added as origins — they 301 to the apex, so the SPA never
  runs on the www origin.

`name` must be unique within the client-env — it keys the workspace, the bucket and the AWS
resource names, so two SPAs in the same account never collide.

**`www_redirect`** adds `www.<domain>` to the cert, the distribution aliases and DNS, plus a
CloudFront Function that returns a **301 to the apex** (preserving path + query string) — so the
apex stays the single canonical URL. Prefer this over listing `www` in
`subject_alternative_names`, which would serve duplicate content on two URLs. It's worth enabling
when the zone is a **root domain** (`sayer.com`); it's pointless when the zone is already a
subdomain (`sayer.ecolors.app`), since nobody types `www.sayer.ecolors.app`.

The stack builds S3 (private) + CloudFront (OAC) + an ACM cert in **us-east-1** + Route 53
**ALIAS A/AAAA** records. The apex works precisely because it's an ALIAS, not a CNAME — which is
also why the APIs stay on a subdomain via App Runner (see `docs/contracts.md`).

**Terraform does not upload the site.** The FE repo's CI does (`examples/app-repo/deploy-frontend.yml`):
build → `aws s3 sync` into an immutable **`<version>/`** prefix. It does NOT make the version live.
**`version` is load-bearing:** it drives CloudFront's `origin_path` — which release is served — so
promoting or rolling back is just editing `version` and applying the frontend workspace (no rebuild;
old versions stay in the bucket). Invalidate the distribution (`invalidate_command` output) to make
the cutover instant. Full flow in [`docs/runbook-rollback-fe.md`](./runbook-rollback-fe.md).

Apply order: foundation (creates the zone) → frontend. The factory adds a run-trigger.

**The SPA calling the API** is app-side, not infra: build the FE with
`VITE_API_URL=https://api.<zone_name>` and enable **CORS** on the API for the apex origin
(`https://<zone_name>`) — apex and `api.` subdomain are different origins.

## Manual (without the factory)
1. Create a `foundation` workspace (working dir `stacks/foundation`), set `foundation.tfvars.example` vars, apply.
2. Delegate the zone (name servers).
3. Create a `service` workspace (working dir `stacks/service`), set `service.tfvars.example` vars, apply.

## App image contract
The container must: listen on `container_port` (default 8080), expose `health_path` (default `/health`),
and read its DB connection string from the env var `ConnectionStrings__<key>` (App Runner injects it from SSM).
The service also injects **`APP_VERSION`** (from `version`) and **`APP_VERSION_DATE`** (stamped
automatically when `version` changes) env vars — the `/health` endpoint should read these and
return the running version + release date.
