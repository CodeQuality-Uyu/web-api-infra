# 03 — Identidad, acceso y gobierno

> **Documento 3 de la serie de arquitectura.** Explica en profundidad **cómo se autentica y
> autoriza** todo en la plataforma —tanto las máquinas (pipelines) como las personas— y el **marco
> de gobierno** de AWS Organizations dentro del cual viven las cuentas. Combina lo que construimos
> en este repo con lo que EColors ya tenía documentado.
>
> Está escrito **sin dar nada por sabido**. Cada concepto se define al aparecer.

## 0. Dos preguntas, dos mundos

Toda la seguridad de acceso responde a dos preguntas distintas, que se resuelven con mecanismos
distintos:

| Pregunta | Quién | Mecanismo |
|---|---|---|
| ¿Cómo despliega un **pipeline** sin guardar claves? | Máquinas (HCP Terraform, GitHub Actions) | **OIDC** → rol IAM temporal |
| ¿Cómo entra una **persona** a la consola de AWS? | Humanos (equipo cloud) | **IAM Identity Center** (SSO) |
| ¿Qué **límite máximo** tiene una cuenta, haga lo que haga? | Toda la cuenta | **SCP** de AWS Organizations |

Las tres capas se combinan. Vamos una por una.

---

## 1. Conceptos base de IAM (los ladrillos)

- **Principal:** quién hace una acción (un usuario, un rol, un servicio).
- **Rol IAM:** una identidad *sin credenciales permanentes* que un principal puede **asumir** por
  un rato. Tiene dos partes:
  - **Trust policy (relación de confianza):** define **quién** puede asumirlo y **bajo qué
    condiciones**.
  - **Permission policies:** definen **qué** puede hacer una vez asumido.
- **STS (Security Token Service):** el servicio de AWS que **emite credenciales temporales** cuando
  alguien asume un rol. Duran poco (acá, 1 hora) y después se vencen.
- **Política:** un documento JSON con `Allow`/`Deny` sobre acciones y recursos.
- **Permisos efectivos:** la **intersección** de todas las capas. Un `Deny` en cualquier capa gana
  siempre. Una capa nunca *concede* más de lo que otra permite.

  ```
  Permisos efectivos = IAM policy ∩ SCP ∩ Permission boundary ∩ Session policy
  (y cualquier Deny explícito corta todo)
  ```

---

## 2. OIDC: desplegar sin claves de larga vida

### 2.1 El problema que resuelve

La forma vieja de que un pipeline despliegue en AWS era darle una **access key** (una credencial
permanente). Problema: esa clave hay que guardarla, rotarla, y si se filtra, el atacante tiene
acceso hasta que alguien la revoque. Es la causa de una fracción enorme de los incidentes en la
nube.

**OIDC (OpenID Connect)** elimina la clave permanente. En vez de guardar un secreto, el pipeline
**demuestra su identidad** ante AWS con un token de vida corta, y AWS se lo cambia por credenciales
temporales. No hay nada guardado que se pueda robar.

### 2.2 Las piezas

- **Identity Provider (IdP):** el sistema externo cuya palabra AWS decide confiar. Acá hay dos:
  - `app.terraform.io` — HCP Terraform (para desplegar infraestructura).
  - `token.actions.githubusercontent.com` — GitHub Actions (para publicar imágenes y frontends).
- **`aud` (audience):** un valor que el token *debe* traer, para que un token emitido para otra
  cosa no sirva. Acá: `aws.workload.identity` (TFC) y `sts.amazonaws.com` (GHA).
- **`sub` (subject):** *quién específicamente* dentro del IdP. Es lo que permite decir "solo el
  workspace X de la organización Y", no cualquiera con una cuenta de TFC.
- **OIDC provider en IAM:** el objeto en la cuenta AWS que representa la confianza en ese IdP.

### 2.3 El flujo, paso a paso

```
1. El pipeline arranca un run.
2. El IdP (TFC/GitHub) le emite un token OIDC (un JWT firmado) con claims: iss, aud, sub, ...
3. El pipeline llama a STS: AssumeRoleWithWebIdentity, presentando ese token.
4. STS valida: ¿el token está firmado por un IdP en el que confío? ¿el aud coincide?
   ¿el sub matchea la condición de la trust policy del rol?
5. Si todo cierra → STS devuelve credenciales TEMPORALES (1 hora).
6. El pipeline despliega con esas credenciales. Al vencer, desaparecen.
```

Nada de esto involucra una clave guardada. La seguridad está en las **condiciones** de la trust
policy: aunque alguien tenga una cuenta de TFC, su token no va a matchear el `sub` permitido.

### 2.4 Cómo lo hace ESTE repo

La factory pone en **cada workspace** (foundation, service, frontend) dos variables de entorno:

```
TFC_AWS_PROVIDER_AUTH = true
TFC_AWS_RUN_ROLE_ARN  = arn:aws:iam::<cuenta-del-cliente>:role/tfc-deploy
```

HCP Terraform ve esas variables y, en cada run, hace el flujo de arriba: pide un token, asume el
rol `tfc-deploy` de **esa** cuenta, y despliega. El ARN del rol **determina en qué cuenta se
despliega** — y eso sale de `aws_account_id` en `clients.auto.tfvars`. Ni una clave de AWS en
ningún lado.

### 2.5 El rol `tfc-deploy` (creado por `stacks/bootstrap`)

Este repo trae el código para crear el rol automáticamente, en
[`modules/account-oidc`](../../modules/account-oidc) + [`stacks/bootstrap`](../../stacks/bootstrap).
Está **basado en el rol documentado de EColols** (`TerraformDeploymentRole-*` en Confluence), con
tres diferencias deliberadas:

1. **Se llama `tfc-deploy`** (nombre unificado que espera la factory), no
   `TerraformDeploymentRole-Ecolors-Prod`.
2. **Permite lo que usan estos stacks** (App Runner, RDS, ECR, S3, CloudFront, ACM, Route 53, SSM,
   Secrets Manager, CodeBuild, EC2/VPC, KMS acotado). El rol documentado permitía `ecs:*` porque
   esa era la arquitectura vieja; el nuestro usa `apprunner:*`.
3. **Permite gestión de roles IAM de workload.** El rol documentado *denegaba* crear roles porque
   en ECS los roles se pre-creaban; nuestros stacks **crean roles en el momento** (el rol de acceso
   de App Runner, el de instancia, el de CodeBuild, el de migraciones), así que el rol de deploy
   necesita poder crearlos.

**Los guardrails (lo que NIEGA), que es lo que lo hace seguro:**

- **Nada de identidades ni cuenta:** deny de `iam:*User*`, `iam:*Group*`, `iam:*AccessKey*`,
  `organizations:*`, `account:*`, `billing`, `budgets`, `ce`. Si el código de Terraform se
  equivoca o alguien lo compromete, **no puede** crear usuarios, tocar la organización ni la
  facturación.
- **Anti-escalada (self-tampering):** deny explícito de cualquier cambio sobre **el propio rol
  `tfc-deploy`** y sobre **el OIDC provider que confía en TFC**. Un pipeline comprometido no puede
  ampliarse los permisos a sí mismo ni redirigir la confianza.
- **`PassRole` acotado:** solo puede "pasar" roles a los servicios que legítimamente corren nuestro
  workload (App Runner, CodeBuild, EC2 del bastión). No puede pasar un rol privilegiado a cualquier
  servicio.

**Por qué es un paso aparte (huevo y gallina):** el rol `tfc-deploy` es el que Terraform *asume*
para desplegar. No puede crearse a sí mismo con ese mismo rol. Por eso `stacks/bootstrap` **no** usa
OIDC ni backend remoto: estado local y credenciales de admin. Ver
[stacks/bootstrap/README.md](../../stacks/bootstrap/README.md).

**Pero solo la cuenta management se bootstrapea a mano.** Es el ancla de confianza (no hay cuenta
padre de la que asumir). Para las cuentas hijas, [`stacks/account-bootstrap`](../../stacks/account-bootstrap)
lo automatiza: corre una vez como `tfc-org-admin`, asume el `OrganizationAccountAccessRole` de cada
cuenta vendida y crea ahí su `tfc-deploy` — sin apply local por cuenta.

### 2.6 La condición `sub`: qué falta decidir

La trust policy documentada de EColors restringe por **proyecto de TFC**:

```
"organization:ColorLabs:project:EColors-nonprod:workspace:*"
```

Nuestra factory hoy **no asigna proyecto** a los workspaces, así que el módulo usa por defecto un
`sub` más amplio:

```
"organization:ColorLabs:project:*:workspace:*:run_phase:*"
```

Esto permite que **cualquier** workspace de la organización `ColorLabs` asuma el rol. Es más laxo
que lo documentado. Dos formas de cerrarlo (queda **pendiente de decisión**):
- Asignar cada workspace a un **proyecto** de TFC en la factory, y restringir el `sub` por proyecto.
- O pasar `tfc_allowed_subs` explícito al bootstrap con la lista exacta de workspaces/proyectos.

### 2.7 El otro rol OIDC: GitHub Actions (`github-deploy`)

Paralelo a `tfc-deploy`, cada cuenta de cliente-env expone un rol **`github-deploy`** para que los
pipelines de GitHub Actions publiquen artefactos **sin claves de larga vida**:
- publican imágenes en **ECR** (push, *no* crear repos — los repos los crea la `foundation`),
- suben el build del frontend a **S3** (`s3 sync` sobre los buckets del FE),
- invalidan **CloudFront**.

**Dónde vive:** módulo `modules/github-deploy-role`, instanciado por `stacks/foundation` (una vez por
cuenta, sobre el mismo OIDC provider de GitHub que ya usan las migraciones). El ARN sale del output
`github_deploy_role_arn` de la foundation.

**Confianza acotada** (trust policy): solo los repos declarados y solo `main` + tags —
`repo:CodeQuality-Uyu/<repo>:ref:refs/heads/main` y `.../refs/tags/*`. La lista de repos la arma la
factory: por cada cliente-env toma el `github_repo` de cada backend y cada frontend
(`clients.auto.tfvars`) y se la pasa a la foundation (`var.github_repos`). Mismo rigor que el de TFC,
pero sobre GitHub.

**Permisos mínimos:** el push de ECR está scopeado a los ARNs de los repos de *ese* cliente-env
(`values(module.ecr.repository_arns)`) — sin `ecr:CreateRepository`. El `s3 sync` está scopeado a los
buckets del FE de ese cliente-env (`var.frontend_buckets`). `GetAuthorizationToken` y la invalidación
de CloudFront son `Resource: *` por diseño de AWS (no aceptan recurso acotado).

**Modelo de versión declarativo:** el workflow **solo** construye y publica el artefacto (imagen o
build). *No* toca Terraform ni variables de TFC. La versión que corre se promueve editando `version`
en `clients.auto.tfvars` (App Runner con `auto_deploy = false`). Los ejemplos alineados a nuestro
esquema están en [`examples/app-repo/`](../../examples/app-repo/) (`build-and-push.yml`,
`deploy-frontend.yml`).

---

## 3. IAM Identity Center: el acceso de las **personas**

OIDC es para máquinas. Para que una **persona** entre a la consola de AWS de un cliente, EColors usa
**IAM Identity Center** (antes *AWS SSO*), documentado en la guía de nuevo licenciatario.

- Centraliza el login: la persona se autentica **una vez** contra el IdP corporativo.
- Identity Center le da acceso a las cuentas que le corresponden, asumiendo un **rol** vía STS
  (mismo principio que OIDC: credenciales temporales, cero claves permanentes).
- Se organiza con **Permission Sets** (plantillas de permisos): `ps-admin`, `ps-poweruser`,
  `ps-readonly`, que se asignan a **grupos** (`grp-sayer-prod-admin`, `grp-sayer-nonprod-readonly`).

```
Persona → IdP corporativo → IAM Identity Center → STS → rol en la cuenta destino
```

> Esta capa **no la administra este repo** — es responsabilidad de la cuenta *management* de la
> organización. Se documenta acá para dar el cuadro completo: es el mecanismo por el cual, por
> ejemplo, se corre el `stacks/bootstrap` a mano con una sesión de admin.

---

## 4. AWS Organizations: el marco de gobierno

Todas las cuentas de cliente viven dentro de una **AWS Organization**, que es la estructura que da
facturación consolidada y control central. Es la capa más externa.

### 4.1 Piezas

- **Management account:** la cuenta raíz de la organización. No corre workloads; gobierna.
- **Organizational Unit (OU):** un contenedor **lógico** de cuentas. No tiene recursos; agrupa. Las
  políticas puestas en una OU **se heredan** hacia abajo.
- **Cuenta miembro:** donde viven los recursos reales (una por client-env, en nuestro modelo).
- **Service Control Policy (SCP):** el **límite máximo** de lo que se puede hacer en una cuenta,
  *aunque IAM lo permita*. Una SCP **nunca concede** permisos, solo **restringe**.

### 4.2 Estructura de OUs — **environment-first** (ADR 0008)

**Principio:** las OUs existen para aplicar **SCPs**, así que agrupan por lo que comparte política =
el **ambiente**. El aislamiento entre clientes vive en la **cuenta separada**, no en la OU.

```
Root
├── Security          → cuentas log-archive + audit
├── Infrastructure    → cuenta infrastructure (DNS compartido) + finops (costos)
├── Workloads
│   ├── Prod          → SCP prod:    deny root, deny borrar CloudTrail/Config, deny regiones
│   └── NonProd       → SCP nonprod: bloquear instancias caras, bloquear regiones
└── Suspended         → SCP restrictiva; cuentas viejas en decomisión
```

- **Cuentas de workload**: `<client>-<env>` bajo `Workloads/<env>`. El **tenant** es el tag
  `Tenant`, no una OU.
- **Cuentas de plataforma** (no-workload) bajo Security/Infrastructure: `stacks/management` las
  vende con `platform_accounts`.
- **Una SCP por OU de ambiente** cubre a todos los clientes de ese ambiente — guardrails uniformes.
- Las OUs viejas por cliente (EColors/Sayer/Ulbrika) se decomisionan a mano.

Qué va en cada OU funcional (cuentas **dedicadas**, no workloads):
- **Security**: `log-archive` (logs inmutables de toda la org) + `audit` (GuardDuty/Security Hub).
- **Infrastructure**: `infrastructure` (**DNS compartido**: `ecolors.app` + rol de delegación, en
  `stacks/infrastructure`) y `finops` (**tooling de costos**). A futuro: red compartida.
- **Suspended**: cuentas en decomisión.

**Dónde va la gestión de gastos:** la facturación consolidada vive en la cuenta management (no se
mueve). El **tooling** de costos va en la cuenta `finops` bajo Infrastructure, con lectura del
CUR/Cost Explorer — así management queda mínima. La vista de billing consolidado se da con el
permission set `BillingReadOnly` de Identity Center sobre la management.

**Por qué el DNS se movió a Infrastructure:** la cuenta management debe tener **solo gobierno**
(org, OUs, SCPs, vending, Identity Center). El DNS compartido es un servicio de plataforma → vive
en la cuenta `infrastructure`, no en management.

Esto **reduce el movimiento lateral**: aunque alguien tome una cuenta, la SCP de su OU de ambiente
le corta acciones aunque tenga admin *dentro* de la cuenta. (El diseño tenant-first que había en
Confluence se descartó — ver ADR 0008 para el porqué y el trade-off.)

### 4.3 SCPs — implementadas en `stacks/management`

Cinco políticas, todas **deny-based** (se combinan con el `FullAWSAccess` por defecto, que queda —
no hay lockout por allow-list). No aplican a la cuenta management (root break-glass preservado).

| SCP | Se pega en | Qué niega |
|---|---|---|
| **baseline** | Root | salir de la org, uso del usuario root, apagar CloudTrail/Config/GuardDuty |
| **region-lock** | Workloads | acciones fuera de `allowed_regions` (us-east-1, us-east-2); servicios globales exentos |
| **prod** | Workloads/Prod | borrar KMS keys, deshabilitar cifrado EBS por defecto, S3 public-access a nivel cuenta |
| **nonprod** | Workloads/NonProd | instancias EC2 caras/aceleradas (GPU, `*.metal`, muy grandes) |
| **suspended** | Suspended | casi todo (solo lectura/soporte/billing) — congela cuentas en decomisión |

> ⚠️ **Las SCPs son el control de mayor riesgo del sistema** — una mal puesta te bloquea o rompe
> los deploys, y **no se pueden testear sin aplicarlas**. Por eso:
> - Las **políticas siempre se crean** (revisables en consola), pero la **atadura está gated**:
>   `enable_scps = false` por defecto, y `enable_region_lock = false` aparte (el de mayor riesgo).
> - Ninguna niega acciones que hace `tfc-deploy`, así que los deploys siguen funcionando.
> - Recomendado: activar primero en **nonprod/suspended**, verificar un deploy, y recién ahí prod +
>   region-lock.
> - Requiere el tipo `SERVICE_CONTROL_POLICY` **habilitado** en la org (default en orgs con all
>   features).

### 4.4 Cómo se relaciona con `tfc-deploy`

Son **capas apiladas**, no alternativas:

```
Lo que tfc-deploy puede hacer  =  (Allow del rol)  −  (Deny del rol)  ∩  (SCP de la OU)
```

Aunque el rol `tfc-deploy` permita `ec2:*`, si la SCP de la OU bloquea `us-east-1`, Terraform **no
puede** crear nada ahí. Por eso el gobierno de Organizations y los permisos del rol se diseñan
juntos: el rol define *lo que la herramienta necesita*, la SCP define *el techo que la cuenta nunca
puede superar*.

## 4.5 La cuenta management SÍ se gestiona (aparte) — `stacks/management`

La cuenta raíz (`ecolors`) es la **management**: contiene la Organization, Identity Center y la
facturación consolidada, y **no corre workloads** — solo roles y gobierno. Se gestiona con
[`stacks/management`](../../stacks/management), **separado del factory a propósito**:

| | Factory (client-envs) | `stacks/management` (raíz) |
|---|---|---|
| Cuenta | Sub-cuenta del cliente | Management/root |
| Rol OIDC | `tfc-deploy` (perfil *workload*) | **`tfc-org-admin`** (perfil *org-admin*) |
| Permisos | Infra; **deny** de org/billing | Organizations/SSO/billing; **deny** de credenciales estáticas + self-tampering |
| Estado | Uno por client-env | Uno, singleton |

**Por qué no se mezclan:** los guardrails de `tfc-deploy` niegan `organizations:*` y `billing:*` a
propósito. La raíz necesita justo lo contrario. Mezclarlas obligaría a debilitar el guardrail y a
que un error del factory pudiera tocar la organización. Por eso: otra cuenta, otro estado, otro rol
—con perfil `org-admin`— y un solo workspace `management` (no lo estampa el factory, porque la raíz
no es un client-env).

**Qué gestiona hoy:** los **permission sets** de Identity Center y sus asignaciones a grupos, sobre
la cuenta management. Incluye por defecto un **`BillingReadOnly`** (policy `AWSBillingReadOnlyAccess`
asignada a un grupo) — que resuelve el "no puedo entrar con un rol a ver solo la facturación". La
Organization, las OUs y las cuentas **ya existen y NO se recrean**; las SCPs son el próximo paso.

> ⚠️ **El gotcha de billing:** provisionar el permission set no alcanza. En la consola de la cuenta
> management hay que activar **"IAM user and role access to Billing information"**. Es un switch de
> cuenta **sin recurso de Terraform**; sin él, la consola de billing niega el acceso aunque la
> policy esté bien. Ver [stacks/management/README.md](../../stacks/management/README.md).

**Account vending:** `stacks/management` también **crea la OU y la cuenta de un cliente nuevo**
(`ou-<cliente>` + `ou-<cliente>-<env>` + `acc-<cliente>-<env>`, con email raíz por plus-addressing
`aws+<cliente>-<env>@<dominio>`). Solo vendea clientes **nuevos**; las cuentas hechas a mano quedan
afuera. Tres advertencias que valen oro:

1. **Las cuentas son casi permanentes.** `destroy` intenta *cerrar* la cuenta (90 días de
   suspensión). Cada cuenta lleva `prevent_destroy`: sacar un cliente de la lista **da error** en
   vez de cerrar su cuenta. A propósito.
2. **Vendear NO reemplaza el bootstrap.** La cuenta nueva solo trae `OrganizationAccountAccessRole`;
   hay que crear su `tfc-deploy`. Eso lo hace `stacks/account-bootstrap` (asume ese rol desde
   management), no un apply local por cuenta. La cadena de alta es:
   **management (crea cuenta) → account-bootstrap (crea rol) → factory (crea infra).**
3. **El `aws_account_id` pasa de input a output.** Management crea la cuenta y muestra su id en
   `vended_account_ids`; ese id se copia una vez a `clients.auto.tfvars`. Decisión: se mantiene
   explícito en git (auditable), no derivado por remote state.

Las **SCP** que documentó EColols (§4.2–4.3) son el techo de gobierno; `stacks/management` es el
lugar natural para codificarlas cuando se quiera moverlas de "hechas a mano" a Terraform.

---

## 5. Etiquetas (tags) de gobierno

EColols define tags obligatorios para costos y auditoría: `Tenant`, `Environment`, `Owner`,
`CostCenter`, `ManagedBy`, `Criticality`.

Nuestros stacks aplican hoy `Client`, `Environment`, `ManagedBy` (vía `default_tags`). **Faltan**
`Owner`, `CostCenter`, `Criticality` — agregarlos es trivial (un `default_tags` más rico) y mejora
el desglose de costos por cliente en Cost Explorer. Registrado en `deuda-tecnica.md`.

---

## 6. Resumen

- **Máquinas → OIDC.** Ningún pipeline guarda claves de AWS. `tfc-deploy` (creado por
  `stacks/bootstrap`) es lo que HCP Terraform asume; su ARN fija la cuenta destino. `github-deploy`
  (creado por `stacks/foundation`) es su par para GitHub Actions: push a ECR + `s3 sync` del FE +
  invalidar CloudFront, con permisos acotados a los recursos de esa cuenta.
- **Personas → IAM Identity Center.** SSO con credenciales temporales, fuera del alcance del repo.
- **Techo → SCP de Organizations.** El límite máximo por cuenta, que gana sobre cualquier permiso.
- **Los permisos efectivos son la intersección** de todo, y cualquier `Deny` corta. El rol
  `tfc-deploy` viene con guardrails que impiden tocar identidades, la organización, la facturación y
  —clave— a sí mismo.
- **Pendientes registrados:** restringir el `sub` por proyecto de TFC y sumar los tags de gobierno
  faltantes (el rol OIDC de GitHub ya está implementado como `github-deploy`).
