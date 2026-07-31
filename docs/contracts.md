# Contracts (the load-bearing conventions)

These are the only cross-boundary couplings. Keep them true.

## Foundation → Service (remote_state)
The service stack reads its client's foundation outputs via `terraform_remote_state`
(`var.foundation_workspace`). Required foundation outputs:

| output | used by service for |
|---|---|
| `vpc_id`, `private_subnet_ids` | App Runner VPC connector, CodeBuild |
| `db_clients_sg_id` | App Runner connector SG + CodeBuild SG (shared RDS allows it) |
| `zone_id` | App Runner custom-domain + validation records |
| `github_oidc_provider_arn` | migrations CI role trust |
| `ecr_repository_urls` | `image_uri` = `ecr_repository_urls[app]:image_version` |
| `db_address`, `db_port` | App Runner + CodeBuild DB host/port (shared RDS) |
| `db_connection_string_arns` | per connection: `ConnectionStrings__<key>` -> ARN of `[db_name]` |
| `db_connection_string_names` | migration job's connection string (the app's own db) |
| `db_connection_string_kms_key_arn` | instance/CodeBuild role KMS Decrypt |

The shared RDS itself (instance, subnet group, SG, databases + connection strings, bastion
ingress) lives in **foundation** — one instance per client-env, holding the distinct set of
databases the apps connect to (a db may be shared by several apps). See `docs/adr/0006`.

## Cross-env shared DB (provider → consumer, cross-account)
A connection with `source = "<provider>-foundation"` reaches a db in another client-env. See
`docs/adr/0007`. Extra couplings, all via HCP remote state (org-level, cross-account safe):

| output | direction | used for |
|---|---|---|
| provider `db_connection_strings` (sensitive) | provider → consumer service | consumer re-stores it in its own SSM, injects it |
| consumer `nat_eip` | consumer foundation → provider foundation | provider allowlists it on the public RDS SG |

Requires: same HCP org (factory guarantees), `global_remote_state` on foundations (factory sets),
and the provider RDS `publicly_accessible` (factory sets `db_public` on referenced providers).

## AWS account
`aws_account_id` per client-env is the single source of truth for **where** a client deploys.
The factory turns it into the OIDC role ARN (`TFC_AWS_RUN_ROLE_ARN`, env var on every workspace)
and every stack enforces it via `allowed_account_ids`. Silo-per-client (0001) is therefore
enforced by the provider, not just by convention.

## Naming
- Foundation workspace: `{client}-{env}-foundation`
- Service workspace: `{client}-{app}-{env}-service`
- Resource prefix: foundation `{client}-{env}`, service `{client}-{app}-{env}`
- ECR repository: `{client}-{app}-{env}` (created by foundation, one per app)
- Shared RDS: `{client}-{env}-pg` (foundation, one per client-env)
- Logical databases: the distinct `db_name`s across all apps' `connections` (may be shared)
- SSM connection string: `{ssm_prefix}/{env}/db/{db_name}/connection-string`
- App env var: `ConnectionStrings__{key}` — one per connection
- Version env vars (injected): `APP_VERSION` = `image_version`, `APP_VERSION_DATE` = auto-stamped when `image_version` changes

## Domain
`subdomain` must be a **subdomain of the client zone**, never the zone apex
(App Runner binds via CNAME, and Route 53 can't CNAME a zone apex).

The **apex belongs to the frontend**: the `frontend` stack serves the SPA there via CloudFront
plus Route 53 **ALIAS A/AAAA** records, which *are* allowed at an apex. So per client-env:
`<zone_name>` → SPA (CloudFront/S3), `api.<zone_name>` → App Runner. The frontend reads only
`zone_id` / `zone_name` from the foundation.

## Versioning
Every workspace tracks a **git tag**, not a branch. See `VERSIONING.md`.

## Image promotion
App Runner `auto_deploy` is **off** — Terraform owns which image runs. To release: push
an immutable `{client}-{app}-{env}:{version}` image to ECR, bump `version` in
`clients.auto.tfvars`, apply the factory (updates the service workspace's `image_version`),
then run the service workspace. The plan promotes App Runner's `image_identifier` and
`APP_VERSION`, and re-stamps `APP_VERSION_DATE` (a `time_static` keyed on `image_version`), so
`/health` reflects the release. Use immutable version tags (not `latest`) so each version is a
distinct, plannable artifact.

## Blob storage (multimedia)
A backend opts in with an empty `blobs` block in `clients.auto.tfvars`:
```hcl
blobs = {}   # CDN domain -> assets.<zone_name>; bucket -> {client}-{app}-{env}-blobs
```
Both `domain` and `bucket_name` are **computed** and only overridden when needed (a client-env with
blobs on more than one backend must set an explicit `domain`, since the default `assets.<zone_name>`
would collide). That creates a **private** S3 bucket (no public access; only CloudFront reads via
OAC) plus a **CloudFront CDN** (ACM cert + Route 53 alias in the client-env zone). The app side
matches `ecolors-web-api`'s `AWSBlobService`:

- **Upload** = presigned **PUT** (browser → S3 directly, SSE-S3). The bucket's **CORS** allows PUT
  from the same browser origins derived for this backend's API CORS (the SPA that calls the API is
  the one uploading). Fresh objects land under the `temporary/` prefix.
- **Confirm** = the app **copies** the object from `temporary/` to a permanent prefix
  (`MoveObjectFromTemporary` — a `CopyObject`, so the temp original stays and is reaped by the
  **lifecycle rule that expires `temporary/` after 1 day**). No infra impact: the copy targets an
  arbitrary prefix that the lifecycle never touches, and the instance role's `bucket/*` grant
  already covers `CopyObject` (Get on source + Put on dest).
- **Read** = the app builds `{Blob__CloudFrontDomain}/{key}` for CDN-served assets (product
  images), or a presigned **GET** for private downloads (Excels).
- **Runtime IAM**: the App Runner **instance role** gets `s3:GetObject/PutObject/DeleteObject` on
  `bucket/*` and `s3:ListBucket` on the bucket (the latter so a missing key returns 404, which the
  app's not-found handling relies on). No static keys — the SDK uses the instance role.
- **Injected env** (so `BlobSection` binds with no hand-editing): only the infra-derived
  `Blob__BucketName` and `Blob__CloudFrontDomain`, plus `Blob__Type=aws`. `Blob__TemporaryObject`
  defaults to `temporary` on both the app and the bucket lifecycle, so it's injected **only** when
  overridden; `AWS__Region` isn't injected (App Runner sets `AWS_REGION`). Override any of these by
  adding the key to the backend's `settings` — a plain entry there wins over the auto value.

> Everything under the bucket is reachable through the CDN by key (keys are GUIDs, so unguessable).
> That's intended for images; treat truly-private blobs as obscured-by-key, not access-controlled.
