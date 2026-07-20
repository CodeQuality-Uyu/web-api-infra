data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "random_password" "master" {
  length           = 24
  special          = true
  # Excludes characters that break connection strings / URLs: " ' \ / ; ? &
  override_special = "!#$%*+-.:<=>^_~"
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnets"
  subnet_ids = var.subnet_ids
  tags       = merge(var.tags, { Name = "${var.name}-db-subnets" })
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds-sg"
  description = "Postgres SG for ${var.name}"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-rds-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "from_sg" {
  for_each                     = toset(var.allowed_sg_ids)
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

# External access: consumer client-envs (other accounts) reaching this shared RDS over its
# public endpoint. Locked to their NAT egress IPs; SSL is enforced (rds.force_ssl below).
resource "aws_vpc_security_group_ingress_rule" "from_cidr" {
  for_each          = toset(var.external_allowed_cidrs)
  security_group_id = aws_security_group.rds.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  description       = "External consumer egress IP"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.rds.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.name}-pg"
  family = "postgres${split(".", var.engine_version)[0]}"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, { Name = "${var.name}-pg" })
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-pg"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = var.publicly_accessible

  port     = 5432
  username = var.master_username
  password = random_password.master.result

  multi_az                            = var.multi_az
  backup_retention_period             = var.backup_retention_days
  deletion_protection                 = var.deletion_protection
  iam_database_authentication_enabled = var.iam_authentication
  auto_minor_version_upgrade          = true
  copy_tags_to_snapshot               = true

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-pg-final"

  tags = merge(var.tags, { Name = "${var.name}-pg", Environment = var.environment })
}

locals {
  # Npgsql-style base connection string (Database appended per db_name below).
  conn_base = "Host=${aws_db_instance.this.address};Port=${aws_db_instance.this.port};Username=${var.master_username};Password=${random_password.master.result};Ssl Mode=Require;Trust Server Certificate=true"
}

# One SecureString per logical DB — consumed by App Runner as a runtime secret.
resource "aws_ssm_parameter" "conn" {
  for_each = toset(var.db_names)

  name        = "${var.ssm_prefix}/${var.environment}/db/${each.value}/connection-string"
  description = "Connection string for ${each.value} on ${aws_db_instance.this.identifier}"
  type        = "SecureString"
  value       = "${local.conn_base};Database=${each.value}"

  tags = merge(var.tags, { Environment = var.environment, DBName = each.value })
}

# Master credentials as JSON (admin / migrations).
resource "aws_secretsmanager_secret" "master" {
  name                    = "rds/${var.name}/master"
  recovery_window_in_days = var.environment == "prod" ? 30 : 0
  tags                    = merge(var.tags, { Environment = var.environment })
}

resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({
    engine   = "postgres"
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    username = var.master_username
    password = random_password.master.result
    dbname   = "postgres"
  })
}
