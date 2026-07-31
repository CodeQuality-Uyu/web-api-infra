# bootstrap — one-time per AWS account

Creates the OIDC federation for HCP Terraform and the **`tfc-deploy`** role that every other
workspace in the account assumes. **This resolves onboarding blocker B-02.**

## Why it's separate and applied by hand

The role created here is the one HCP Terraform assumes to deploy. It cannot be created *by* a
workspace that already uses that role — chicken-and-egg. So bootstrap is applied **once per
account, with elevated credentials**, using **local state** (no `cloud {}` backend).

## How to run (once per account)

```bash
cd stacks/bootstrap
# Log in with an admin session — e.g. IAM Identity Center (SSO):
aws sso login --profile <account-admin-profile>
export AWS_PROFILE=<account-admin-profile>

terraform init
terraform apply \
  -var 'aws_account_id=273733837144' \
  -var 'tfc_organization=ColorLabs'
# Region is fixed to us-east-1 in the provider (IAM is global, so it only matters for the provider).
```

Repeat for each account (`sayer`, `ulbrika`, `ecolors-prod`, `ecolors-nonprod`, …).

The output `role_arn` must equal what the factory computes for that client-env:
`arn:aws:iam::<account>:role/tfc-deploy`. If it doesn't, either fix `role_name` here or
`tfc_role_name`/`aws_role_name` in the factory.

## If the app.terraform.io OIDC provider already exists

Only one OIDC provider per URL per account is allowed. If it's already there (e.g. created by
hand per the old runbook), pass `-var 'create_tfc_oidc_provider=false'` and the role will
reference the existing one.

## What the role can and cannot do

- **Allows** exactly the services these stacks touch (App Runner, RDS, ECR, S3, CloudFront, ACM,
  Route 53, SSM, Secrets Manager, CodeBuild, EC2/VPC, scoped KMS) plus the IAM role management the
  stacks perform.
- **Denies** IAM users/groups/keys, Organizations, billing — and **self-tampering**: it cannot
  modify its own policies or the OIDC provider it trusts (no privilege escalation).

Ported from EColors' documented `TerraformDeploymentRole-*`, adapted for App Runner (the docs
allowed `ecs:*`) and to allow in-stack IAM role creation (the docs denied it because ECS roles
were pre-created). See `docs/arquitectura/03-identidad-y-gobierno.md`.
