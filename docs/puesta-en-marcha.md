# Puesta en marcha y gestión

> El **orden completo** para crear la plataforma desde cero y cómo se opera en el día a día. Ata
> los stacks entre sí (cada uno tiene su README con el detalle). Para agregar un cliente ya con la
> plataforma armada, ver `runbook-alta-cliente.md`.

## Las dos fuentes de verdad

Casi todo sale de dos archivos:

| Archivo | Gobierna | Lo consume |
|---|---|---|
| `stacks/management/*.tfvars` | Org, OUs, SCPs, **cuentas** (vending), accesos de Identity Center | `stacks/management` (cuenta raíz) |
| `factory/clients.auto.tfvars` | Clientes: frontends, backends, bases, versiones, config, CORS | El **factory** (estampa workspaces) |

El resto se **deriva**: account ids, ids de zona DNS, dominios, orígenes CORS, roles de AWS, y hasta
la conexión VCS de los workspaces. Todo se despliega en **us-east-1** (fijo en el provider de cada
stack; la región no es una variable).

## Los planos y stacks

```
GOBIERNO (cuenta raíz + plataforma)             WORKLOADS (por cliente)
─────────────────────────────────              ──────────────────────
stacks/management       → org, OUs, SCPs,       factory            → estampa los workspaces
                          vending, Identity        (usa provider tfe)
                          Center
stacks/account-bootstrap → tfc-deploy en cada   stacks/foundation  → VPC, RDS, ECR, zona, deleg.
                          cuenta hija (auto)     stacks/service     → App Runner + migraciones [+ blobs]
stacks/infrastructure   → zona DNS +            stacks/frontend    → S3 + CloudFront
                          rol de delegación
stacks/bootstrap        → rol OIDC (solo la
                          cuenta management)
```

---

## Creación desde cero (una sola vez)

Leyenda: 🖐️ manual · 🤖 terraform · ⏳ espera de AWS.

### A. Cuenta raíz y organización

| # | Paso | Tipo |
|---|---|---|
| A1 | La cuenta management (CCL, `975050152436`) e IAM Identity Center ya existen | 🖐️ (hecho) |
| A2 | `stacks/bootstrap` en la cuenta raíz con `role_name=tfc-org-admin`, `role_profile=org-admin` (sesión SSO admin, **estado local**). Es el único bootstrap manual: es el ancla de confianza, no hay cuenta padre de la que asumir | 🖐️🤖 |
| A3 | Crear el workspace HCP `management` (dynamic credentials → `tfc-org-admin`) | 🖐️ |
| A4 | **Importar la org**: `terraform import aws_organizations_organization.this o-kf9lzgx3ia` | 🖐️ |
| A5 | Setear `management_account_id`, `platform_accounts`, `clients_to_vend` (con email root único por cuenta), `org_id`, y aplicar → crea OUs, SCPs, habilita tipos de política, **vende las cuentas NUEVAS** (workload + plataforma), permission sets | 🤖 |
| A6 | Activar el toggle **"IAM access to Billing"** en la consola de la raíz | 🖐️ |
| A7 | AWS aprovisiona las cuentas nuevas (minutos–horas) | ⏳ |

> Las cuentas se crean **nuevas** (`sayer-prod`, `ulbrika-prod`, `ecolors-prod`, `ecolors-nonprod`,
> `infrastructure`, …). Las viejas hechas a mano se decomisionan aparte (a `Suspended`, luego cerrar).

### B. Bootstrap de las cuentas hijas — **automatizado**

| # | Paso | Tipo |
|---|---|---|
| B1 | Crear el workspace HCP `account-bootstrap` → `stacks/account-bootstrap` (dynamic credentials → `tfc-org-admin`; habilitar que lea el state de `management`). Aplicar → asume el `OrganizationAccountAccessRole` de **cada** cuenta vendida y crea ahí su `tfc-deploy` + OIDC provider | 🤖 |

> Reemplaza el viejo "correr bootstrap a mano en cada cuenta". Requiere que A7 haya terminado (el
> `OrganizationAccountAccessRole` tiene que existir para poder asumirlo). Ver
> `stacks/account-bootstrap/README.md`.

### C. Cuenta infrastructure (DNS)

| # | Paso | Tipo |
|---|---|---|
| C1 | Workspace HCP `infrastructure` → `stacks/infrastructure` (dynamic credentials → `tfc-deploy` de esa cuenta). Setear `aws_account_id` (output `platform_account_ids["infrastructure"]` de management) + `org_id`. Aplicar → crea la zona `ecolors.app` + el rol `dns-delegation` | 🤖 |
| C2 | En GoDaddy, delegar `ecolors.app` a los `parent_zone_name_servers` del output (una vez) | 🖐️ |

> Los outputs `parent_zone_id` y el account id **los lee el factory solo** (remote state) — no se pegan.

### D. El factory

| # | Paso | Tipo |
|---|---|---|
| D1 | Completar `factory/clients.auto.tfvars`: `organization`, `management_workspace = "management"` y los clientes. **No** se pega account id (se deriva de management), ni `dns_parent_*` (se deriva de infrastructure), ni `oauth_token_id` (se resuelve de la conexión VCS por `vcs_service_provider`) | 🖐️ |
| D2 | Crear el workspace HCP del **factory** → working dir `factory`, con `TFE_TOKEN` (token de HCP) y permiso de leer el state de `management` e `infrastructure`. Aplicar → estampa foundation/service/frontend + variables + run-triggers + dynamic credentials, y **conecta cada workspace hijo al repo** (VCS + branch = `version_tag`; el working dir ya lo fija por stack) | 🤖 |

> El factory **no crea infra AWS**, solo configura workspaces en HCP. Un `apply` acá reconfigura muchos
> workspaces (concentra riesgo).

### E. Correr los workloads

| # | Paso | Tipo |
|---|---|---|
| E1 | Correr los **foundation** (los hijos ya vienen con VCS + credenciales) → VPC, RDS compartida, ECR, zona del cliente, OIDC de GitHub, rol `github-deploy`, **delegación NS automática** en `ecolors.app` | 🤖 |
| E2 | Cargar los `secret_values` (map sensible) en cada `*-service` que declare `secret_settings` | 🖐️ |
| E3 | Publicar la **primera imagen** de cada backend en ECR (App Runner no arranca contra un repo vacío) | 🖐️ |
| E4 | Correr **service** y **frontend** → App Runner + dominio custom + migraciones (+ blobs); S3 + CloudFront | 🤖 |
| E5 | **Primera migración** de cada backend (workflow `migrate.yml` → CodeBuild) + publicar contenido del **frontend** | 🖐️ |

> Hasta que la delegación de GoDaddy (C2) propague, los certs ACM y los dominios custom quedan
> `pending` — es esperable.

---

## Gestión (día a día)

| Tarea | Qué se toca | Comando |
|---|---|---|
| **Cliente nuevo** | management (vend) → account-bootstrap → `clients.auto.tfvars` | ver `runbook-alta-cliente.md` |
| **Backend/frontend nuevo** | agregar a `backends`/`frontends` | apply factory → run el workspace |
| **Nueva versión (backend)** | `version` del backend | push imagen → apply factory → run service |
| **Nueva versión (frontend)** | `version` del frontend | subir build a `<version>/` → apply factory → run frontend → invalidar |
| **Config / secretos / CORS** | `settings` / `secret_values` / `calls` | apply factory → run service |
| **Nueva base** | `connections` del backend | apply factory → run foundation → migrar |
| **Base compartida a otra cuenta** | `source` en la connection | run-triggers hacen el resto |
| **Cambiar guardrails** | SCPs en `stacks/management` | apply management |

**El patrón general:** editás el tfvars → aplicás el factory (actualiza variables de workspaces) →
corrés el workspace afectado. El factory nunca crea infra en AWS; solo configura workspaces.

---

## Dependencias de orden (lo que NO se puede saltear)

```
management (vende cuentas) → account-bootstrap (crea tfc-deploy) → factory (lee account ids)
infrastructure (zona)      → foundations (delegan NS)            → services/frontends
```

- El factory **lee los account ids y el parent_zone_id del remote state** de management e
  infrastructure → esos dos se aplican primero.
- `account-bootstrap` corre **después** de que management venda las cuentas (necesita el
  `OrganizationAccountAccessRole`), y **antes** que cualquier workspace hijo (que asume `tfc-deploy`).
- Las foundations **asumen el rol dns-delegation** de infrastructure → infrastructure primero.
