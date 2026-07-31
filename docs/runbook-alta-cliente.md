# Runbook — alta de un cliente nuevo (de cero a producción)

> Flujo end-to-end para incorporar un licenciatario nuevo, **marcando explícitamente cada paso
> manual**. Cuenta raíz: `975050152436` (ecolors). Org de HCP: `ColorLabs`.

Leyenda:
- 🖐️ **MANUAL** — lo hace una persona (consola, CLI, editar un archivo, aprobar un plan).
- 🤖 **TERRAFORM** — un `apply` (local o en HCP).
- ⏳ **AWS** — espera asíncrona de AWS (no depende de vos).

---

## Fase 0 — Prerrequisitos de la organización (una sola vez, ya deberían estar)

| # | Paso | Tipo |
|---|---|---|
| 0.1 | Cuenta management `975050152436` existe, con AWS Organizations e IAM Identity Center habilitados | 🖐️ (hecho) |
| 0.2 | Bootstrap del rol de la raíz: `stacks/bootstrap` con `role_name=tfc-org-admin`, `role_profile=org-admin` | 🖐️🤖 una vez |
| 0.3 | Crear el workspace HCP `management` (tag `management`, dir `stacks/management`, env vars OIDC → `tfc-org-admin`) | 🖐️ una vez |
| 0.4 | Activar el toggle **"IAM user and role access to Billing information"** en la cuenta raíz | 🖐️ una vez |
| 0.5 | Cuenta `infrastructure`: vendearla (management `platform_accounts`) → bootstrap vía `account-bootstrap` → aplicar `stacks/infrastructure` (crea la zona `ecolors.app` + rol `dns-delegation`) → delegar en GoDaddy a sus name servers. El factory lee `dns_parent_account_id`/`dns_parent_zone_id` del remote state (management + infrastructure) — **no se setean a mano** | 🖐️🤖 una vez |
| 0.6 | Crear el workspace HCP `account-bootstrap` (dir `stacks/account-bootstrap`, dynamic creds → `tfc-org-admin`, con acceso al state de `management`) | 🖐️ una vez |

---

## Fase 1 — Vending de la cuenta (en la cuenta raíz)

| # | Paso | Tipo |
|---|---|---|
| 1.1 | Conseguir **emails raíz únicos** para cada cuenta nueva (uno por ambiente, nunca usados en AWS) | 🖐️ |
| 1.2 | Agregar el cliente a `clients_to_vend` en el workspace `management` (client + environments con email) | 🖐️ editar |
| 1.3 | `apply` del workspace `management` → crea las cuentas `nuevo-prod`/`nuevo-nonprod` bajo `Workloads/Prod` y `Workloads/NonProd` (las OUs funcionales ya existen) | 🤖 |
| 1.4 | AWS aprovisiona las cuentas (minutos a horas; puede requerir activación/aumento de límite) | ⏳ |
| 1.5 | (El factory lee `vended_account_ids` del remote state de management — no hace falta copiar ids a mano) | 🤖 |

> ⚠️ Las cuentas son casi permanentes (`prevent_destroy`). Sacar un cliente de la lista **da error**,
> no cierra la cuenta.

---

## Fase 2 — Bootstrap de las cuentas nuevas — **automatizado**

| # | Paso | Tipo |
|---|---|---|
| 2.1 | Agregar las dos cuentas nuevas (prod + nonprod) a `stacks/account-bootstrap`: un `provider "aws"` aliased + un `module` por cuenta (los aliases no se generan dinámicamente, es un bloque por cuenta) | 🖐️ editar |
| 2.2 | `apply` del workspace `account-bootstrap` → asume el `OrganizationAccountAccessRole` de cada cuenta nueva y crea su `tfc-deploy` + OIDC provider | 🤖 |
| 2.3 | Verificar el output `bootstrapped_role_arns` = `arn:aws:iam::<id-nuevo>:role/tfc-deploy` por cuenta | 🖐️ |
| 2.4 | *(opcional)* Asignar un permission set de Identity Center para que humanos entren a la cuenta nueva | 🖐️ |

> Reemplaza el viejo "asumir el rol y correr bootstrap local en cada cuenta". Requiere que 1.4 haya
> terminado (el `OrganizationAccountAccessRole` tiene que existir para asumirlo).

---

## Fase 3 — Infraestructura del cliente (factory + stacks)

| # | Paso | Tipo |
|---|---|---|
| 3.1 | Agregar el cliente a `factory/clients.auto.tfvars`: `zone_name`, `frontends`, `backends`. **El `aws_account_id` NO se pone** — el factory lo lee del vending de management por remote state. La región es us-east-1 fija (no se configura) | 🖐️ editar |
| 3.2 | `apply` del factory → crea workspaces foundation/service/frontend + variables + run-triggers + dynamic credentials, y **conecta cada workspace al repo** (VCS automático; el `oauth_token_id` se resuelve de la conexión VCS de la org). Cargar los `secret_values` en los `*-service` que declaren `secret_settings` | 🤖 |
| 3.3 | Correr el workspace **foundation** → VPC, zona Route 53, OIDC de GitHub, repos ECR, RDS compartida, **y la delegación NS en la zona padre (cross-account, automática)** | 🤖 (HCP) |
| 3.4 | ~~Delegación DNS manual~~ **Automática** (requiere el setup único de Fase 0.5) | 🤖 |
| 3.5 | Publicar la **primera imagen** de cada backend en ECR (App Runner no arranca contra un repo vacío) | 🖐️ (CI del app repo) |
| 3.6 | Correr los workspaces **service** y **frontend** → App Runner + dominios + migraciones; S3 + CloudFront + ACM | 🤖 (HCP) |
| 3.7 | Disparar la **primera migración** de cada backend (crea la base + el esquema) | 🖐️ (workflow) |
| 3.8 | Publicar el contenido del **frontend**: build → `s3 sync` → invalidación de CloudFront | 🖐️ (CI del FE repo) |
| 3.9 | Configurar **CORS** de la API (si el FE la llama) — se deriva solo del factory, pero se aplica al correr el service | 🤖 |

---

## Fase 4 — Si el cliente consume recursos compartidos de `ecolors-prod`

(Aplica a licenciatarios que usan la base `Admin` y/o el login del authprovider — como Sayer/Ulbrika.)

| # | Paso | Tipo |
|---|---|---|
| 4.1 | El factory recalcula la topología: agrega el NAT EIP del cliente al allowlist del RDS de `ecolors-prod` y su origin al CORS del authprovider | 🤖 (deriva) |
| 4.2 | Un **run-trigger** re-encola el foundation de `ecolors-prod` y el service del authprovider | 🤖 |
| 4.3 | **Aprobar** esos planes en `ecolors-prod` (a menos que tengan auto-apply) | 🖐️ |

---

## Resumen: SOLO los pasos manuales

Si querés la lista corta de "qué tengo que hacer con las manos":

1. **(una vez)** Bootstrap del rol de la raíz + workspaces `management` / `account-bootstrap` / `infrastructure` + toggle de billing. *(Fase 0)*
2. Conseguir **emails únicos** para las cuentas nuevas. *(1.1)*
3. **Editar** `clients_to_vend` y aprobar el apply. *(1.2–1.3)*
4. **Editar** `stacks/account-bootstrap` (2 cuentas nuevas) y aprobar el apply → crea `tfc-deploy`. *(2.1–2.2)*
5. **Editar** `clients.auto.tfvars` con el detalle del cliente (sin account id — se deriva). *(3.1)*
6. **Cargar** los `secret_values` en los `*-service` que declaren secretos. *(3.2)*
7. **Publicar la primera imagen** de cada backend. *(3.5)*
8. **Aprobar** los applies de foundation/service/frontend. *(3.3, 3.6)*
9. **Primera migración** + **publicar el FE**. *(3.7–3.8)*
10. Si comparte con ecolors-prod: **aprobar** el re-apply de ese entorno. *(4.3)*

> ✅ **La delegación DNS ya NO es manual.** La foundation escribe sus NS en la zona padre
> cross-account, asumiendo el rol `dns-delegation`. Requiere el setup único de la Fase 0.5.

> ✅ **El account id ya NO se copia a mano** — el factory lo lee del output `vended_account_ids` de
> management por remote state. Requiere que el workspace `management` comparta su estado (state
> sharing) con el del factory.

> ✅ **El bootstrap por cuenta ya NO es manual** — `stacks/account-bootstrap` corre una vez en la
> cuenta management (como `tfc-org-admin`), asume el `OrganizationAccountAccessRole` de cada cuenta
> vendida y crea su `tfc-deploy`. Para un cliente nuevo solo se agregan sus dos bloques de provider +
> module y se re-aplica ese workspace.

> ✅ **El VCS ya NO se conecta a mano** — el factory conecta cada workspace hijo al repo (resuelve el
> `oauth_token_id` de la conexión VCS de la org). El único bootstrap manual que queda es el de la
> cuenta management (el ancla de confianza).
