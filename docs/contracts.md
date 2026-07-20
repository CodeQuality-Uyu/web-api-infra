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
