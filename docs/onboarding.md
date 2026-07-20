# Onboarding

## New client
Add a client block to `factory/clients.auto.tfvars` (client, environment, zone_name, apps —
each app is `{ app, version, connections, subdomain, github_repo, settings?, secret_settings? }`,
where `connections` is a list of `{ key, db_name, migrate? }`) and apply the factory. It creates the
`{client}-{env}-foundation` workspace + one `{client}-{app}-{env}-service` workspace per app,
wires their variables, and adds a run-trigger so services apply after the foundation.

Then, once: apply the foundation (creates the VPC, zone, and one ECR repo per app), copy its
`name_servers` output into your registrar (GoDaddy) to delegate the zone, and push the first
image (`{client}-{app}-{env}:{version}`) to ECR — App Runner needs it before the service applies.

## New app for an existing client
Add another entry to that client's `apps` list and re-apply the factory. Re-apply the
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
creates the **distinct set** of every `db_name` referenced (a db shared by several apps is
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
`{ key = "Admin", db_name = "EColorsAdminProd", source = "ecolors-prod-foundation" }`.

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
