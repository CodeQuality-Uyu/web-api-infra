# 0001 — Silo per client via workspaces

**Status:** Accepted

Each client gets an isolated stack (own VPC, RDS, App Runner services), realized as
Terraform Cloud workspaces sourced from this shared repo — not a shared multi-tenant
cluster. Chosen for blast-radius isolation, per-client cost visibility, and simple
data separation. Cost is higher per client; acceptable for the current client profile.
