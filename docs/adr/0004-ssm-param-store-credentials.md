# 0004 — DB credentials via SSM Parameter Store

**Status:** Accepted

The database module writes one SecureString connection string per logical DB to SSM
Parameter Store; App Runner injects them as runtime secrets (`ConnectionStrings__<key>`).
A Secrets Manager JSON master secret is also kept for admin/migrations. Matches the
existing platform convention. Open item: no automatic rotation yet (tracked separately).
