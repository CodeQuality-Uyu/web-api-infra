# 0005 — Migrations via CodeBuild-in-VPC

**Status:** Accepted

Because App Runner offers no ECS Exec / RunTask, automated DB migrations run in a CodeBuild
project placed inside the VPC (reuses the shared `db_clients` SG that RDS allows). The app's
GitHub Action assumes a scoped OIDC role and calls `codebuild:StartBuild`; the migration
scripts + buildspec live in the app repo. The SSM bastion remains the break-glass admin path.
