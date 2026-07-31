# infrastructure — shared platform account

Runs in the dedicated **infrastructure** account (under the `Infrastructure` OU, vended by
`stacks/management`). Holds shared platform services — today the **parent DNS zone**
(`ecolors.app`) and the cross-account **`dns-delegation`** role.

Moved out of the management account on purpose: the management account should hold **org
governance only**. Shared services (DNS, and later networking, artifact repos) live here.

## Setup (once)

1. Vend the account: add `infrastructure` to `platform_accounts` in `stacks/management` and apply.
2. Bootstrap it: assume its `OrganizationAccountAccessRole` and run `stacks/bootstrap`
   (`role_name=tfc-deploy`, `role_profile=workload`).
3. Create an HCP workspace tagged `infrastructure` → this stack, with OIDC env vars pointing at
   the infra account's `tfc-deploy`. Set `aws_account_id`, `org_id`, apply.
4. **Delegate at the registrar (GoDaddy):** point `ecolors.app` at this zone's
   `parent_zone_name_servers` output. One-time, manual.
5. In the factory, set `dns_parent_account_id` = the infra account id and
   `dns_parent_zone_id` = the `parent_zone_id` output.

## ⚠️ Migrating `ecolors.app` from the management account

`ecolors.app` currently lives in the management account (zone `Z04978981S0KQM044JRJY`). A hosted
zone **cannot be moved between accounts** — this stack creates a **new** zone here. Cutover:

- Recreate any records the old zone served (the client-subdomain NS delegations get written
  automatically by the foundations; other records must be copied by hand).
- Repoint GoDaddy to the new zone's name servers (step 4). At that moment the old zone stops
  being authoritative — same all-or-nothing switch described in `docs/arquitectura/02-dns.md`.
- Once verified, delete the old zone in the management account.
