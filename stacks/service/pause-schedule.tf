# Optional overnight pause for cost savings (nonprod). Two EventBridge Scheduler schedules call
# the App Runner Pause/Resume APIs directly (universal targets — no Lambda). While paused, App
# Runner does not bill for provisioned instances.
locals {
  pause_enabled = var.pause_cron != null
}

data "aws_iam_policy_document" "scheduler_assume" {
  count = local.pause_enabled ? 1 : 0
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  count              = local.pause_enabled ? 1 : 0
  name               = "${local.name}-apprunner-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume[0].json
  tags               = local.tags
}

resource "aws_iam_role_policy" "scheduler" {
  count = local.pause_enabled ? 1 : 0
  name  = "${local.name}-apprunner-pause-resume"
  role  = aws_iam_role.scheduler[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["apprunner:PauseService", "apprunner:ResumeService"]
      Resource = module.service.service_arn
    }]
  })
}

resource "aws_scheduler_schedule" "pause" {
  count = local.pause_enabled ? 1 : 0
  name  = "${local.name}-pause"

  flexible_time_window { mode = "OFF" }
  schedule_expression          = var.pause_cron
  schedule_expression_timezone = var.schedule_timezone

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:apprunner:pauseService"
    role_arn = aws_iam_role.scheduler[0].arn
    input    = jsonencode({ ServiceArn = module.service.service_arn })
  }
}

resource "aws_scheduler_schedule" "resume" {
  count = local.pause_enabled ? 1 : 0
  name  = "${local.name}-resume"

  flexible_time_window { mode = "OFF" }
  schedule_expression          = var.resume_cron
  schedule_expression_timezone = var.schedule_timezone

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:apprunner:resumeService"
    role_arn = aws_iam_role.scheduler[0].arn
    input    = jsonencode({ ServiceArn = module.service.service_arn })
  }
}
