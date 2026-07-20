# --- VPC connector: lets App Runner reach the private RDS ---
# Uses the shared db_clients SG (which RDS already allows), so there is no
# dependency cycle between this module and the database module.
resource "aws_apprunner_vpc_connector" "this" {
  vpc_connector_name = "${var.name}-conn"
  subnets            = var.subnet_ids
  security_groups    = var.connector_sg_ids
  tags               = var.tags
}

# --- Access role: pull image from ECR ---
data "aws_iam_policy_document" "access_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["build.apprunner.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "access" {
  name               = "${var.name}-apprunner-access"
  assume_role_policy = data.aws_iam_policy_document.access_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "access_ecr" {
  role       = aws_iam_role.access.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

# --- Instance role: read the DB connection-string secrets at runtime ---
data "aws_iam_policy_document" "instance_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["tasks.apprunner.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name}-apprunner-instance"
  assume_role_policy = data.aws_iam_policy_document.instance_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "instance" {
  count = length(var.secret_source_arns) > 0 ? 1 : 0

  statement {
    sid       = "ReadSecrets"
    actions   = ["ssm:GetParameters", "ssm:GetParameter", "secretsmanager:GetSecretValue"]
    resources = var.secret_source_arns
  }

  dynamic "statement" {
    for_each = length(var.kms_key_arns) > 0 ? [1] : []
    content {
      sid       = "DecryptSecrets"
      actions   = ["kms:Decrypt"]
      resources = var.kms_key_arns
    }
  }
}

resource "aws_iam_role_policy" "instance" {
  count  = length(var.secret_source_arns) > 0 ? 1 : 0
  name   = "${var.name}-apprunner-instance-policy"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.instance[0].json
}

# --- The App Runner service ---
resource "aws_apprunner_service" "this" {
  service_name = "${var.name}-api"

  source_configuration {
    auto_deployments_enabled = var.auto_deploy
    authentication_configuration {
      access_role_arn = aws_iam_role.access.arn
    }
    image_repository {
      image_identifier      = var.image_uri
      image_repository_type = "ECR"
      image_configuration {
        port                          = var.port
        runtime_environment_variables = var.runtime_env
        runtime_environment_secrets   = var.runtime_secrets
      }
    }
  }

  instance_configuration {
    cpu               = var.cpu
    memory            = var.memory
    instance_role_arn = aws_iam_role.instance.arn
  }

  network_configuration {
    ingress_configuration {
      is_publicly_accessible = true
    }
    egress_configuration {
      egress_type       = "VPC"
      vpc_connector_arn = aws_apprunner_vpc_connector.this.arn
    }
  }

  health_check_configuration {
    protocol = "HTTP"
    path     = var.health_path
  }

  tags = var.tags
}

# --- Custom domain: App Runner issues & renews the TLS cert itself ---
resource "aws_apprunner_custom_domain_association" "this" {
  domain_name          = var.domain_fqdn
  service_arn          = aws_apprunner_service.this.arn
  enable_www_subdomain = false
}

# CNAME the subdomain to App Runner + the cert-validation records.
resource "aws_route53_record" "app" {
  zone_id = var.zone_id
  name    = var.domain_fqdn
  type    = "CNAME"
  ttl     = 300
  records = [aws_apprunner_custom_domain_association.this.dns_target]
}

resource "aws_route53_record" "validation" {
  for_each = {
    for r in aws_apprunner_custom_domain_association.this.certificate_validation_records : r.name => r
  }
  zone_id         = var.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 300
  records         = [each.value.value]
  allow_overwrite = true
}
