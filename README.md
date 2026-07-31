# web-api-infra

Reusable Terraform for deploying **web APIs on AWS App Runner backed by Postgres (RDS)**,
reachable from a custom domain — one isolated stack per client, driven by HCP Terraform
workspaces. A single repo (this one) is the template; each client/app is a workspace.

## What you get per app
- **App Runner** service (managed HTTPS + autoscaling, TLS cert issued for the custom domain)
- A logical database on the client-env's **shared RDS Postgres** (private, one instance per
  client-env, one database per app), reached via an App Runner VPC connector
- DB credentials delivered as **SSM SecureString** connection strings (`ConnectionStrings__<key>`)
- **CodeBuild-in-VPC** migration runner triggered from the app's GitHub Action (OIDC)
- **ECR repo** (`{client}-{app}-{env}`, immutable tags) with Terraform-pinned version promotion
- Optional **blobs** (private S3 + CloudFront + OAC) on its own subdomain

## Layout
```
modules/    network · dns · ecr · database · service (App Runner) · migrations · blobs · frontend · account-oidc · dns-delegation-role
stacks/
  bootstrap/      per AWS account (once): OIDC provider + tfc-deploy / tfc-org-admin role (by hand)
  management/     the root account: org + OUs + SCPs + account vending + Identity Center (billing)
  infrastructure/ shared platform account: parent DNS zone (ecolors.app) + dns-delegation role
  foundation/   per client-env: VPC + SSM bastion + hosted zone + GitHub OIDC + ECR repos + shared RDS
  service/      per app:        App Runner + domain + migrations (+ optional blobs)
  frontend/     per frontend:   SPA (S3 + CloudFront + ACM + ALIAS records)
factory/    tfe provider — stamps all workspaces + vars from clients.auto.tfvars
examples/   foundation/service tfvars + app-repo GitHub workflows
docs/       puesta-en-marcha.md · arquitectura/ · runbook-alta-cliente.md · deuda-tecnica.md · contracts · adr/
```

## Quick start
1. Set `REPLACE_ORG` in `stacks/*/terraform.tf` (or use `TF_CLOUD_ORGANIZATION`).
2. Fill `factory/clients.auto.tfvars` and apply the factory to create workspaces.
3. Delegate each client zone's `name_servers` at your registrar.
4. Foundation applies, then service applies. Push an image, run the migrate workflow.

## Notes
- Two stacks per client, not seven. See `docs/adr/0003`.
- One **shared RDS per client-env** (one database per app), owned by foundation. See `docs/adr/0006`.
- Workspaces pin a **git tag**, never a branch. See `VERSIONING.md`.
- App Runner runs a **Terraform-pinned image version**, not `:latest`. Release by pushing
  `{client}-{app}-{env}:{version}` and bumping `version` in `clients.auto.tfvars`. See `docs/contracts.md`.
- The App Runner subdomain must not be the zone apex. See `docs/contracts.md`.
- Not validated with `terraform validate` in the authoring environment — run
  `terraform init && validate` in each stack before first apply.
