# 0003 — Two stacks: foundation + service

**Status:** Accepted

Per client: one `foundation` (network, bastion, zone, OIDC — changes rarely) and N
`service` stacks (one per app: App Runner + domain + migrations). (Since 0006 the shared
RDS moved into foundation; originally each service stack owned its own RDS.) Collapses the
former 7-workspaces-per-client into 2, and turns most cross-workspace `remote_state`
string coupling into typed, plan-time module wiring. The only surviving cross-stack read
is foundation → service (see contracts.md).
