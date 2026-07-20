# 0006 — Shared RDS per foundation (one database per app)

**Status:** Accepted (refines 0003)

The RDS instance moves from the per-app **service** stack up into the per-client-env
**foundation** stack: one Postgres instance per `{client}-{env}`, with one logical database
per app (`replace(app, "-", "_")`) and one SSM SecureString connection string each. Service
stacks no longer create a database — they read `db_address` / `db_port` /
`db_connection_string_arns[db_name]` from foundation and wire only App Runner + migrations.

Chosen because N apps in a client-env previously meant N RDS instances (e.g. `ecolors-nonprod`
had 5), which is costly and operationally heavy for what is logically one datastore per
environment. Data isolation is preserved at the **database** level (separate db + credentials
per app), while instance-level cost, patching, and backups are shared.

Trade-offs: apps in a client-env now share an instance's blast radius (a bad instance-level
change affects all of them) and its capacity (noisy-neighbor). Acceptable — the isolation
boundary that matters here is the **client-env** (still a separate silo per 0001), not the app.
Per-app instances remain possible by instantiating the `database` module in a service stack if
one app ever needs true instance isolation.

This supersedes 0003's placement of RDS in the service stack; the two-stack split itself
(foundation + service) is unchanged.
