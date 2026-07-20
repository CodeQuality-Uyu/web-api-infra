# Apply order

```
foundation   (network + SSM bastion + hosted zone + GitHub OIDC + ECR repos + shared RDS)
   │  delegate name servers at the registrar (one-time per client)
   │  push the first image: {client}-{app}-{env}:{version} to ECR
   ▼
service      (App Runner + custom domain + CodeBuild migrations [+ blobs])
```

Foundation owns the **shared RDS** (one instance per client-env, one database per app) and
the ECR repos. App Runner can't start against an empty repo, so the pinned image version
must be pushed **before** the service applies. Foundation apply → build & push the version →
service apply (pulls `ecr_repository_urls[app]:image_version`, reads its DB connection string
from `db_connection_string_arns[db_name]`).

The factory adds a run-trigger so a foundation apply queues its services. A service apply only
reads foundation outputs — App Runner's connector reuses the shared `db_clients` SG the RDS
already allows, and `migrations` reads the DB host/port + secret ARN from foundation.

First-time gotcha: App Runner custom-domain validation (and, if used, the blobs ACM cert)
won't complete until the zone's name servers are delegated at the registrar.
