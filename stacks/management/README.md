# management — the root (management) account

Governance for the **management/root account** (`ecolors`). It holds **no workloads** — only
org-wide concerns: IAM Identity Center access (permission sets + assignments) and, later, SCPs.
The Organization, OUs and member accounts already exist and are **not** recreated here.

Kept deliberately separate from the client factory: different account, different state, and a
**different role** (`tfc-org-admin`, org-admin profile) whose permissions are the opposite of the
guardrailed `tfc-deploy`. See `docs/arquitectura/03-identidad-y-gobierno.md`.

## Convention: reference existing, create new

The management account has both pre-existing resources and things this stack adds. The rule:

- **Singletons that already exist and must never be recreated** → always **referenced** via a
  data source, never created: the Organization, the Identity Center instance, and the
  `ecolors.app` hosted zone (a new zone would mint new name servers and break DNS).
- **Incremental resources** → **created**: the foundational OUs + accounts (`clients_to_vend`),
  permission sets (`access`), the `dns-delegation` role. Passing an existing id (e.g.
  `parent_zone_id`) references it; omitting it creates/skips.
- **Truly managing an existing resource** (so Terraform can modify it) needs a deliberate
  `terraform import` — passing an id only *references* (read-only), it does not adopt.

## SCPs (Service Control Policies)

Five deny-based SCPs (`scps.tf`): `baseline` (Root), `region-lock` (Workloads), `prod`, `nonprod`,
`suspended`. See `docs/arquitectura/03-identidad-y-gobierno.md` §4.3.

⚠️ **Highest-risk control here.** Policies are always created; attachment is off by default:
- `enable_scps = true` attaches baseline + prod + nonprod + suspended.
- `enable_region_lock = true` (needs `enable_scps` too) attaches the region lock — enable last.
- Needs the `SERVICE_CONTROL_POLICY` type enabled in the org (default for all-features orgs).

Recommended rollout: enable, watch nonprod + a test deploy, then trust prod; turn on region-lock
only after confirming a deploy works.

## DNS delegation role

`ecolors.app` lives in this account. Set `parent_zone_id` (the zone id) + `org_id` to create the
`dns-delegation` role that client foundations assume to write their NS records. Then in the
factory set `dns_parent_account_id` (this account) + `dns_parent_zone_id`.

## One-time setup

1. **Bootstrap the management account's role** (once, with an admin SSO session):
   ```bash
   cd stacks/bootstrap
   terraform apply \
     -var 'aws_account_id=<MANAGEMENT_ACCOUNT_ID>' \
     -var 'tfc_organization=ColorLabs' \
     -var 'role_name=tfc-org-admin' \
     -var 'role_profile=org-admin' \
     -var 'create_tfc_oidc_provider=false'   # if app.terraform.io OIDC already exists here
   ```
2. **Create one HCP workspace** tagged `management`, working dir `stacks/management`, with env
   vars `TFC_AWS_PROVIDER_AUTH=true` and
   `TFC_AWS_RUN_ROLE_ARN=arn:aws:iam::<MANAGEMENT_ACCOUNT_ID>:role/tfc-org-admin`.
3. Set `management_account_id` (and adjust the `access` groups to your real Identity Center
   group names) and apply.

## Account vending (new clients get an OU + AWS account)

Adding a client to `clients_to_vend` creates `ou-<client>`, `ou-<client>-<env>` and a new account
`acc-<client>-<env>` per environment, with root email `aws+<client>-<env>@<email_domain>`. Existing
accounts (sayer, ulbrika, ecolors-*) are **not** here — they were hand-created and stay out of
Terraform.

**Standard: environment-first** (see `docs/adr/0008`). This stack creates the foundational OUs —
`Security`, `Infrastructure`, `Workloads/Prod`, `Workloads/NonProd`, `Suspended` — and places each
vended account, named `<client>-<env>`, under `Workloads/<env>`. Tenant is the `Tenant` tag, not an
OU. Each account needs its **own unique root email** never used by any AWS account (the old ones
still hold the old addresses, hence the `aws-` prefix).

```hcl
clients_to_vend = [
  { client = "sayer",   environments = [{ env = "prod", email = "aws-sayer-prod@ccl.com" }] },
  { client = "ecolors", environments = [
    { env = "prod",    email = "aws-ecolors-prod@ccl.com" },
    { env = "nonprod", email = "aws-ecolors-nonprod@ccl.com" },
  ] },
]
```

The old per-tenant OUs (EColors/Sayer/Ulbrika) and their ECS+ALB accounts are **not** managed
here — decommission them by hand: move to `Suspended`, close, then delete the empty OUs.

The `vended_account_ids` output feeds the factory: set `management_workspace = "management"` there
and it reads each account id, so `aws_account_id` is never hardcoded. **The management workspace
must share its state** with the factory workspace for that read to work.

### ⚠️ Accounts are effectively permanent
`terraform destroy` on an account tries to **close** it (90-day suspension, hard limits). Every
account carries `prevent_destroy`, so **removing a client from the list ERRORS** instead of closing
their account. That's intentional. The root email is set once and must never change.

### Vending is only step 1 — the full onboarding of a NEW client

```
1. management:  add to clients_to_vend, apply  → OU + account created.
                Read the `vended_account_ids` output for the new account id.
2. bootstrap:   in the NEW account, assume its OrganizationAccountAccessRole and apply
                stacks/bootstrap → creates tfc-deploy (see stacks/bootstrap/README).
3. factory:     add the client to clients.auto.tfvars with aws_account_id = <the new id>,
                apply → workspaces. Then apply foundation/service/frontend as usual.
```

Vending the account does **not** replace the bootstrap: a fresh account only has
`OrganizationAccountAccessRole`; step 2 turns that into the OIDC `tfc-deploy` role.

## ⚠️ The billing gotcha (do this or the role still can't see billing)

Provisioning the `BillingReadOnly` permission set is **not enough** on its own. In the management
account console, go to **Account → "IAM user and role access to Billing information" → Activate**.
This account-level switch has **no Terraform resource**; without it the billing console denies
access even with the correct policy attached.
