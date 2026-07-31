# Hallazgos: Confluence vs. lo construido en este repo

> Resultado de inspeccionar el espacio **AWS** de Confluence de EColors
> (`e-colors.atlassian.net`, páginas 44564481 y descendientes) el 2026-07-18.
> **Propósito:** contrastar lo que la organización ya tiene documentado/implementado con lo que
> construimos en `web-api-infra`, y **surfacear las divergencias antes de que se vuelvan un
> problema.** Esto no es una crítica a ninguno de los dos diseños; es alinear.

## Decisiones tomadas (2026-07-26)

Tras revisar los hallazgos con el equipo:

1. **`web-api-infra` reemplaza a propósito el diseño ECS+ALB.** La migración es *desplegar la
   nueva infra al lado y deprecar la vieja*. → Pendiente: ADR que registre App Runner vs ECS+ALB.
2. **ECS+ALB están desplegados y en uso.** Es una migración real, no green field.
3. **El único punto de fricción de la migración es el DNS** (los nombres colisionan). → Tratado en
   [`02-dns.md`](./02-dns.md).
4. **Región:** ~~nonprod en us-east-2 (Ohio, por costo); prod en us-east-1~~. → **Revisado: el ahorro
   por región es un mito** (la diferencia Ohio vs. Virginia es marginal). **Todo se despliega en
   `us-east-1`**, fijo en el provider de cada stack — la región dejó de ser una variable. A futuro,
   **ARC (disaster recovery) us-east-1 + us-east-2** se ve *después* de alinear la migración.
5. **dev y qa NO son separados** → nuestro `nonprod` único es correcto, sin cambios.
6. **Dominios propios de cliente** (`ulbrika.shopping.com` → nuestro FE, además de
   `ulbrika.ecolors.app`) es un requisito **futuro**. → Diseño en [`02-dns.md`](./02-dns.md) §3.
7. **El rol OIDC `tfc-deploy`** se creó en Terraform ([`stacks/bootstrap`](../../stacks/bootstrap)),
   basado en el documentado. → Resuelve el bloqueante B-02.

## TL;DR

Lo que construimos **no es la misma arquitectura** que la documentada. Difieren en la pieza más
grande (el cómputo), en el modelo de DNS, en la convención de ambientes y en varios nombres
concretos. Hay que decidir explícitamente si `web-api-infra` **reemplaza** el diseño ECS+ALB
documentado, o si debe **alinearse** con él. Antes de aplicar nada, esto se define.

---

## 1. Páginas encontradas

| Página | Contenido |
|---|---|
| **AWS** | Solo un link al AWS SSO start (`d-9066283d8d.awsapps.com/start`) |
| **NonProd** | Integración OIDC (TFC + GHA), rol `TerraformDeploymentRole-ecolors-nonprod`, policy `ECOLORS-BASELINE-GUARDRAILS` |
| **Implementacion ALB** | **Arquitectura de cómputo: ECS + ALB** con enrutamiento por host |
| **DNS-Dominios** | Modelo DNS: una zona `ecolors.app`, subdominios por tenant, wildcard, dominios externos |
| **Nuevo licenciatario / Guia Basica** | AWS Organizations, OUs, Identity Center, SCP, naming, tags |
| **Nuevo licenciatario / Guia Arquitectonica** | Deep-dive de multi-cuenta, OUs, SCP por ambiente |
| **Nuevo licenciatario / OIDC-Roles-Permisos** | JSONs listos de trust policies y permission policies (TFC + GHA) |

---

## 2. Divergencias que importan

### 🔴 D-1 — Cómputo: **ECS + ALB (documentado) vs. App Runner (construido)**

Es la diferencia más grande. La página *Implementacion ALB* describe:

- **Application Load Balancer** público compartido, con **reglas por host** que enrutan cada
  subdominio a un **Target Group** distinto.
- **ECS** (cluster + un service por app) en subredes privadas, cada service registrado en su
  target group, con SG que solo acepta tráfico del SG del ALB.
- Workspaces separados: `dns-acm`, `alb`, `ecs-cluster`, `ecs-service-<app>`.

Nosotros construimos **App Runner** (ADR 0002), que *reemplaza* ALB + target groups + cluster +
registro de servicios por un servicio gestionado. Son modelos incompatibles: o va uno, o va el
otro.

**Implicación:** nuestro ADR 0002 fue tomado sin registrar que **ya existía un diseño ECS+ALB**.
Hay que decidir si App Runner lo sustituye a propósito (y por qué), o si hay que volver a ECS+ALB.
Nota de contexto: la página menciona región **`us-east-2`** en los ARNs de ECR — ver D-5.

### 🔴 D-2 — DNS: **una zona central vs. una zona por cliente**

- **Documentado:** una sola *hosted zone* `ecolors.app`, con **cada tenant como subdominio**
  (`tenant1.ecolors.app`) y un **certificado wildcard `*.ecolors.app`**. Además contempla
  **dominios propios del cliente** (`licenciatario-shop.com`) vía `CNAME` + `TXT` gestionados por
  el cliente.
- **Construido:** una **hosted zone por client-env** (`sayer.ecolors.app` es su propia zona), con
  delegación NS del padre, y **un certificado por recurso** (no wildcard).

Ambos funcionan, pero son estrategias distintas de gobierno de DNS. Y **el caso "dominio propio
del cliente" no está soportado** en lo que construimos — es un requisito que el negocio ya tenía
documentado y que nosotros no contemplamos.

### 🟠 D-3 — Ambientes: **dev + qa vs. un solo nonprod**

Lo documentado tiene **dos ambientes de no producción**: `dev` y `qa` (subdominios
`authprovider.dev.api...` y `authprovider.qa.api...`). Nosotros modelamos **un solo
`nonprod`**. Si dev y qa son ambientes reales y separados, nuestro modelo los está colapsando en
uno.

### 🟠 D-4 — Convención de subdominios distinta

| | Patrón de API |
|---|---|
| **Documentado** | `<app>.<env>.api.ecolors.app` → `authprovider.dev.api.ecolors.app` |
| **Construido** | `<app>.api.<zona>` → `authprovider.api.nonprod.ecolors.app` |

El ambiente va en **posición distinta**, y la raíz es `api.ecolors.app` (central) vs.
`nonprod.ecolors.app` (por client-env). Cualquier cliente/documentación/DNS existente asume el
patrón documentado.

### 🟢 D-5 — Región: **resuelto → todo en us-east-1**

La policy de ECR documentada usaba `arn:aws:ecr:us-east-2:...` y el diseño previo ponía nonprod en
Ohio "por costo". **Se decidió que el ahorro por región es un mito** (Ohio vs. Virginia es marginal):
**todo va a `us-east-1`**, fijo en el provider de cada stack. La región dejó de ser variable, así que
no hay defaults que puedan quedar desalineados. Los ARNs de ECR de la CI apuntan a `us-east-1`.

### 🟡 D-6 — Nombres concretos que no coinciden

Cosas que en nuestro `clients.auto.tfvars` están como placeholders o distintas:

| Concepto | Documentado (real) | En nuestro repo |
|---|---|---|
| Organización TFC | **`ColorLabs`** (proyectos `EColors-nonprod`, `Infra-nonprod`, `MissingOne`) | `REPLACE_ORG` |
| Cuenta AWS (una real) | **`273733837144`** | placeholders `1111...` |
| Rol de deploy TFC | **`TerraformDeploymentRole-Ecolors-Prod`** | default `tfc-deploy` |
| Repo del auth provider | **`ecolors-authentication-provider-web-api`** | `ecolors-auth-provider-web-api` |
| Repo del frontend | **`ecolors-react-web`** (uno solo, React) | (no lo teníamos) |
| Buckets de FE | `admin-ecolors-react-web-dev`, `seller-...`, `demo-...`, `ecolors-react-web-dev` | `ecolors-admin-nonprod-web`, … |

### 🟢 D-7 — Lo que NO cubrimos y ellos ya tenían pensado

La *Guía de Nuevo licenciatario* documenta una capa que nuestro repo **no toca** (y está bien que
no la toque — es responsabilidad de la cuenta management, no de la infra por cliente):

- **AWS Organizations**: management account, OUs (`ou-security`, `ou-shared`, `ou-<tenant>`,
  `-prod`/`-nonprod`), facturación consolidada.
- **IAM Identity Center** para el acceso **humano** (SSO), distinto del OIDC de máquina.
- **SCPs por ambiente**: en prod, deny de root, deny modificar IAM crítico, deny deshabilitar
  Config/CloudTrail; en nonprod, bloqueo de regiones y de instancias caras.
- **Tags obligatorios**: `Tenant`, `Environment`, `Owner`, `CostCenter`, `ManagedBy`,
  `Criticality`. (Nosotros aplicamos `Client`/`Environment`/`ManagedBy`, faltan `Owner`,
  `CostCenter`, `Criticality`.)

Esto es **complementario**, no conflictivo: es el marco de gobierno dentro del cual nuestros
stacks deberían correr.

---

## 3. Coincidencias (lo que sí está alineado)

- **OIDC sin claves de larga vida**, en ambos sentidos (TFC→AWS y GHA→AWS). Idéntico enfoque al
  nuestro. La página tiene los **JSON de trust policy listos** — ver sección 4, resuelven B-02.
- **Aislamiento por cliente vía cuentas separadas**, con blast radius como justificación (igual
  que nuestro ADR 0001).
- **RDS en subred privada**, `/health` como health check, imagen desde ECR, secretos/env para la
  base. Mismo contrato de aplicación.
- **`db.t4g` / naming por tenant**, tags de costo por cuenta.
- **GitHub Actions** publica imágenes y (para FE) hace `s3 sync` + invalidación de CloudFront —
  exactamente el flujo que dejamos en los ejemplos.

---

## 4. Insumo directo para desbloquear B-02 (el rol OIDC)

La página *OIDC-Roles-Permisos* trae los JSON reales. Aplican a nuestro pendiente **B-02** (falta
el rol de federación en cada cuenta), con dos ajustes:

1. **Nombre del rol:** ellos usan `TerraformDeploymentRole-Ecolors-Prod` / `-nonprod`. Nuestro
   factory usa `tfc-deploy` por defecto. Hay que **unificar** — o cambiar nuestro `tfc_role_name`,
   o renombrar el rol. Es exactamente para eso que dejamos `tfc_role_name` parametrizable.

2. **Condición `sub` de la trust policy:** la de ellos restringe por **proyecto** de TFC
   (`organization:ColorLabs:project:EColors-nonprod:workspace:*`). Nuestro factory **no asigna
   proyecto** a los workspaces. O agregamos el proyecto al `tfe_workspace`, o la trust policy debe
   usar `workspace:*` sin proyecto (menos restrictivo). **Decisión pendiente.**

- **Audience:** `aws.workload.identity` (TFC) y `sts.amazonaws.com` (GHA) — coinciden con el
  estándar que asumimos.
- **Permisos:** ellos tienen `ECOLORS-BASELINE-GUARDRAILS` (permite infra, **deny** de
  IAM/Org/Billing) en vez de `AdministratorAccess`. Es una buena base para lo que necesitan
  nuestros stacks; habría que verificar que cubra lo que creamos (App Runner **no** está en su
  lista de `Allow` — tienen `ecs:*`, no `apprunner:*` — otra consecuencia de D-1).

---

## 5. La pregunta estratégica a resolver

**¿`web-api-infra` reemplaza el diseño ECS+ALB documentado, o debe alinearse con él?**

- Si **reemplaza**: hay que actualizar Confluence, registrar en un ADR *por qué* App Runner en
  lugar de ECS+ALB (costo, operación, simplicidad), y decidir qué pasa con lo que ya esté
  desplegado bajo el modelo viejo.
- Si **debe alinearse**: hay que reconsiderar App Runner, o al menos la convención de DNS/ambientes
  y los nombres, para no crear una segunda arquitectura paralela e incompatible.

Todo lo demás (nombres, región, dev/qa, dominios de cliente) se ordena una vez tomada esta
decisión.

---

## 6. Preguntas concretas para confirmar

1. **¿El diseño ECS+ALB está desplegado y en uso, o quedó en documentación?** Cambia si esto es
   una migración o un green field.
2. ~~**¿La región real es `us-east-2`?**~~ → Resuelto: todo en `us-east-1` (ver D-5).
3. **¿dev y qa son ambientes separados** que hay que modelar, o `nonprod` los unifica a propósito?
4. **¿Se necesita soportar dominios propios del cliente** (`licenciatario-shop.com`), o todos los
   licenciatarios viven bajo `*.ecolors.app`?
5. **¿El auth provider es `ecolors-authentication-provider-web-api`?** (nosotros pusimos
   `ecolors-auth-provider-web-api`).
6. **Organización TFC = `ColorLabs`** y ¿los workspaces van dentro de un **proyecto**? (afecta la
   trust policy OIDC).
