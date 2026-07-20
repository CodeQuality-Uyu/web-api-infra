locals {
  name = "${var.client}-${var.environment}"
  tags = merge(var.tags, { Client = var.client, Environment = var.environment })

  # Databases to create on the shared instance (the distinct set referenced by all apps).
  db_names = var.databases
}

module "network" {
  source = "../../modules/network"

  name        = local.name
  cidr_block  = var.vpc_cidr
  enable_nat  = var.enable_nat
  tags        = local.tags
}

module "dns" {
  source = "../../modules/dns"

  name        = local.name
  zone_name   = var.zone_name
  create_zone = var.create_zone
  zone_id     = var.zone_id
  tags        = local.tags
}

# One ECR repository per app, created here (rarely changes, must exist before a
# service stack applies — App Runner can't start against an empty repo). The service
# stack reads ecr_repository_urls and pins a version. See docs/contracts.md.
module "ecr" {
  source = "../../modules/ecr"

  repositories = { for a in var.apps : a => "${var.client}-${a}-${var.environment}" }
  tags         = local.tags
}

# One RDS instance SHARED by all of this client-env's apps, holding the distinct set of
# databases the apps connect to (a db may be shared by several apps). Apps reach it via the
# shared db_clients SG (their App Runner connectors join it); bastion for admin tunneling.
# Service stacks read the per-db connection strings from this stack's outputs. See docs/adr/0006.
module "database" {
  source = "../../modules/database"

  name        = local.name
  environment = var.environment
  ssm_prefix  = var.ssm_prefix
  vpc_id      = module.network.vpc_id
  subnet_ids  = module.network.private_subnet_ids

  allowed_sg_ids = compact([module.network.db_clients_sg_id, module.network.bastion_sg_id])

  # Shared cross-account access: public endpoint + allowlist of consumer NAT EIPs.
  publicly_accessible    = var.db_public
  external_allowed_cidrs = local.consumer_cidrs

  db_names            = local.db_names
  instance_class      = var.db_instance_class
  multi_az            = var.db_multi_az
  deletion_protection = var.db_deletion_protection
  skip_final_snapshot = var.db_skip_final_snapshot
  tags                = local.tags
}

# GitHub Actions OIDC provider — created once per client account, shared by all
# of this client's service stacks for their migration CI roles.
resource "aws_iam_openid_connect_provider" "github" {
  count           = var.enable_github_oidc ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  tags            = local.tags
}
