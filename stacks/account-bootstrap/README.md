# account-bootstrap — the tfc-deploy role in every child account, automated

Replaces the manual, per-account bootstrap (Fase 2). Instead of `aws sso login` + a local
`stacks/bootstrap` apply for each account, this runs **once** in the management account and stands
up `tfc-deploy` in all of them.

## How it works

- Runs in the **management account** as **`tfc-org-admin`** (the role `stacks/bootstrap` created in
  Fase 0). This is a normal HCP workspace with dynamic credentials — no static keys.
- Reads the account ids from the **management** stack's remote state (`vended_account_ids` +
  `platform_account_ids`) — nothing hardcoded.
- For each account, an **aliased AWS provider assumes that account's `OrganizationAccountAccessRole`**
  (auto-created by Organizations, assumable from management) and creates the account's `tfc-deploy`
  role + `app.terraform.io` OIDC provider via `modules/account-oidc` (the same module the manual
  bootstrap uses, `workload` profile).

```
management (tfc-org-admin)
   └── sts:AssumeRole OrganizationAccountAccessRole ──► each child account
                                                          └── creates tfc-deploy + OIDC provider
```

## Run it

1. Make sure **Fase 0-1 are done**: management is bootstrapped (`tfc-org-admin` exists) and applied
   (accounts vended). Wait until AWS finished provisioning the accounts — `OrganizationAccountAccessRole`
   must exist in each before this can assume it.
2. Create an HCP workspace tagged **`account-bootstrap`**, working directory `stacks/account-bootstrap`,
   with dynamic credentials pointing at **`tfc-org-admin`**
   (`TFC_AWS_PROVIDER_AUTH=true`, `TFC_AWS_RUN_ROLE_ARN=arn:aws:iam::<mgmt>:role/tfc-org-admin`).
3. Allow this workspace to **read the management workspace's state** (remote state sharing).
4. Plan → apply.

**Expected result:** `bootstrapped_role_arns` = one `arn:aws:iam::<id>:role/tfc-deploy` per account.
Each must match what the factory computes for that client-env; if not, fix `tfc_role_name` /
`aws_role_name` in the factory.

## Adding an account

Provider aliases can't be generated dynamically, so per new account:
1. add a `provider "aws"` block (alias + `assume_role`) in `providers.tf`, and
2. add a `module` call in `main.tf` with `providers = { aws = aws.<alias> }`.

`finops` is intentionally not bootstrapped (it runs no Terraform yet); add it the same way when it
does.

## Still manual: the management account itself

Fase 0 (management's own `tfc-org-admin`) stays a one-time local `stacks/bootstrap` apply — it's the
trust anchor and there is no parent account to assume from. See `stacks/bootstrap/README.md`.
