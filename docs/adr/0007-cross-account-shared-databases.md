# 0007 — Cross-account shared databases

**Status:** Accepted (extends 0006)

Some apps must reach a database owned by a **different client-env, in a different AWS account**
(e.g. licensee apps `sayer`/`ulbrika` read ecolors' central `Admin` db; central auth reads
`IdentityProvider`). Silo-per-client (0001) gives each client its own VPC + private RDS, so
cross-VPC/cross-account reach is not possible by default.

**Decision.** A connection may set `source = "<provider>-foundation"`. Then:

1. The **provider** client-env's RDS is made **publicly accessible** (`db_public`), locked by
   Security Group to the **NAT egress IPs of the consumer client-envs** (read from consumer
   foundations via HCP remote state) and SSL-enforced (`rds.force_ssl`).
2. Credentials travel via **HCP remote state**, not AWS: the provider foundation exposes a
   `sensitive` `db_connection_strings` output; the consumer service reads it (org-level, so
   cross-account is transparent), re-stores it in **its own** SSM SecureString, and injects it
   as `ConnectionStrings__<key>`. This deliberately avoids cross-account SSM/KMS sharing.
3. Consumers never migrate a shared db — the owning app does (only local `migrate = true` dbs).

The factory computes the provider→consumer topology from `source`, sets `db_public` /
`db_consumer_workspaces`, enables `global_remote_state` on foundations, and wires run-triggers
(provider re-runs on consumer change; consumer services re-run on provider change).

**Trade-offs (accepted):**
- The provider RDS is **publicly reachable** (whole instance, not just the shared db), mitigated
  by a tight SG allowlist + TLS + strong master password.
- The shared secret **spreads**: it lives in the provider's state and lands in each consumer's
  state/SSM. Password rotation requires re-applying consumers (run-trigger automates the run).
- **Ordering:** consumer foundations must apply before the provider foundation on first bring-up.
- Topology must stay a **DAG** (a provider that is also a consumer of its own consumer would cycle).
