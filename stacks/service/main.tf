locals {
  name = "${var.client}-${var.app}-${var.environment}"
  tags = merge(var.tags, { Client = var.client, App = var.app, Environment = var.environment })

  # ConnectionStrings__<key> -> SSM SecureString ARN.
  # Local connections read from this client-env's foundation; external (cross-env, shared)
  # ones from the local SSM param we materialized in remote-external.tf.
  db_conn_secret_arns = merge(
    { for c in local.local_conns : "ConnectionStrings__${c.key}" => local.f.db_connection_string_arns[c.db_name] },
    { for c in local.external_conns : "ConnectionStrings__${c.key}" => aws_ssm_parameter.external_conn[c.key].arn },
  )

  # Databases this app OWNS and migrates (migrate=true). Only local dbs are migratable —
  # external/shared dbs are migrated by their owning app in the provider client-env. An app can
  # own more than one (e.g. authprovider owns AuthProvider + IdentityProvider).
  migrate_db_names = [for c in local.local_conns : c.db_name if c.migrate]

  # Passed to the migration job: db_name -> its connection-string SSM param, + the ARNs to read.
  migrate_conn_ssm  = { for n in local.migrate_db_names : n => local.f.db_connection_string_names[n] }
  migrate_conn_arns = [for n in local.migrate_db_names : local.f.db_connection_string_arns[n]]

  # Full image URI = this app's ECR repo (created by foundation) + the pinned version.
  image_uri = "${local.f.ecr_repository_urls[var.app]}:${var.image_version}"

  # Surfaced to the app (e.g. on /health). Injected values win over var.runtime_env,
  # so they promote together with the image version on every apply.
  version_env = {
    APP_VERSION      = var.image_version
    APP_VERSION_DATE = time_static.version.rfc3339
  }

  # Secret env vars -> their SSM SecureString ARNs, injected as App Runner runtime secrets.
  secret_env_arns = { for k, p in aws_ssm_parameter.secret : k => p.arn }

  # Blob storage config, injected so the app's BlobSection binds without hand-editing settings.
  # Only the values the app can't infer on its own:
  #   - BucketName / CloudFrontDomain: infra-derived, no sensible static default.
  #   - Type=aws: makes the AWS provider bind even if ASPNETCORE_ENVIRONMENT != Production.
  # TemporaryObject is injected ONLY when overridden (the app and the bucket lifecycle both default
  # to "temporary"). Region isn't injected — App Runner sets AWS_REGION and the SDK reads it.
  # Reads are served from CloudFront ({domain}/{key}); uploads use presigned PUT against the bucket.
  blobs_env = var.create_blobs ? merge(
    {
      "Blob__Type"             = "aws"
      "Blob__BucketName"       = var.blobs_bucket_name
      "Blob__CloudFrontDomain" = module.blobs[0].cloudfront_domain
    },
    var.blobs_temporary_object != "temporary" ? { "Blob__TemporaryObject" = var.blobs_temporary_object } : {},
  ) : {}
}

# Captures the release timestamp. `triggers` recomputes the stamp ONLY when image_version
# changes; on any other apply the saved value is held steady (no drift). So APP_VERSION_DATE
# is the moment this version was first promoted.
resource "time_static" "version" {
  triggers = {
    version = var.image_version
  }
}

# One SSM SecureString per secret env var. The value comes from the sensitive `secret_values`
# workspace variable (never git); the app receives it as a runtime secret, decrypted at start.
resource "aws_ssm_parameter" "secret" {
  for_each = toset(var.secret_settings)

  name  = "/app/${var.environment}/secrets/${local.name}/${each.value}"
  type  = "SecureString"
  value = var.secret_values[each.value] # errors if a declared secret has no value — intended
  tags  = local.tags
}

module "service" {
  source = "../../modules/service"

  name             = local.name
  image_uri        = local.image_uri
  auto_deploy      = false # Terraform owns which version runs; promotion = bump image_version + apply
  subnet_ids       = local.f.private_subnet_ids
  connector_sg_ids = [local.f.db_clients_sg_id]
  cpu              = var.cpu
  memory           = var.memory
  port             = var.container_port
  health_path      = var.health_path
  domain_fqdn      = var.subdomain
  zone_id          = local.f.zone_id

  # blobs_env first (lowest precedence): a plain `settings` entry in clients.auto.tfvars overrides
  # any auto value, and version_env always wins.
  runtime_env     = merge(local.blobs_env, var.runtime_env, local.version_env)
  runtime_secrets = merge(local.db_conn_secret_arns, local.secret_env_arns)
  secret_source_arns = concat(
    values(local.db_conn_secret_arns),
    values(local.secret_env_arns),
  )
  kms_key_arns = [local.f.db_connection_string_kms_key_arn]

  # Runtime S3 access to the blobs bucket (Get/Put/Delete + List). Null when blobs are off.
  blobs_bucket_arn = var.create_blobs ? module.blobs[0].bucket_arn : null

  tags = local.tags
}

module "migrations" {
  source = "../../modules/migrations"

  name              = local.name
  github_repo       = var.github_repo
  github_branch     = var.github_branch
  oidc_provider_arn = local.f.github_oidc_provider_arn
  vpc_id            = local.f.vpc_id
  subnet_ids        = local.f.private_subnet_ids
  security_group_ids = [local.f.db_clients_sg_id]
  buildspec         = var.migration_buildspec

  secret_source_arns = local.migrate_conn_arns
  kms_key_arns       = [local.f.db_connection_string_kms_key_arn]
  env = {
    DB_HOST = local.f.db_address
    DB_PORT = tostring(local.f.db_port)
    # The app's OWN databases (migrate=true) as { db_name = <SSM param with its connection
    # string> }. The buildspec fetches each and runs its EF Core context — creating the db on
    # first run (master creds). Usually one db; authprovider owns two. See docs/onboarding.md.
    MIGRATE_CONNECTIONS = jsonencode(local.migrate_conn_ssm)
  }
  tags = local.tags
}

module "blobs" {
  source = "../../modules/blobs"
  count  = var.create_blobs ? 1 : 0

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name             = local.name
  bucket_name      = var.blobs_bucket_name
  domain_fqdn      = var.blobs_domain
  zone_id          = local.f.zone_id
  allowed_origins  = var.blobs_allowed_origins
  temporary_folder = var.blobs_temporary_object
  tags             = local.tags
}
