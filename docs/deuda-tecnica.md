# Deuda técnica y pendientes

Registro vivo de lo que **no** está resuelto. Cada entrada dice el riesgo, las opciones ya
analizadas y **qué información falta para decidir**, de modo que retomarlo no requiera reconstruir
el análisis desde cero.

Estados: `ABIERTO` (identificado, sin decisión) · `DECIDIDO` (hay camino, falta hacerlo) ·
`RESUELTO`.

---

## A. Bloqueantes del primer despliegue

No son deuda de diseño: son pasos de puesta en marcha que faltan.

| # | Pendiente | Detalle |
|---|---|---|
| B-01 | Nada fue validado | Falta `terraform init && validate` en `factory`, `stacks/foundation`, `stacks/service`, `stacks/frontend`, y revisar un plan real |
| B-02 | ~~Falta el rol de federación~~ **Código listo; falta aplicarlo** | Management se bootstrapea a mano una vez ([`stacks/bootstrap`](../stacks/bootstrap), perfil org-admin). Las cuentas hijas las bootstrapea [`stacks/account-bootstrap`](../stacks/account-bootstrap) automáticamente (asume `OrganizationAccountAccessRole` desde management) |
| B-03 | ~~Identificadores de cuenta son marcadores~~ **Resuelto** | Los account id ya no se ponen en `clients.auto.tfvars` — el factory los lee del remote state de management (`vended_account_ids` / `platform_account_ids`) |
| B-04 | Delegación DNS | Una vez por client-env, en el registrador (paso manual inevitable) |

---

## DT-01 — Aislamiento del proveedor de identidad · `ABIERTO` · **Riesgo alto**

### El problema

`ecolors-prod` tiene **una sola instancia** de RDS que aloja tres bases:

```
RDS ecolors-prod-pg
├── EColorsAdminProd            ← los licenciatarios leen Y ESCRIBEN
├── EColorsAuthProviderProd     ← no deberían tener acceso
└── EColorsIdentityProviderProd ← no deberían tener acceso
```

La cadena de conexión que reciben `sayer` y `ulbrika` contiene el **usuario maestro de la
instancia**, no un usuario acotado. Es decir: **cuentas AWS de terceros poseen credenciales
maestras sobre la base de producción que guarda la identidad de toda la plataforma.**

Una inyección SQL o un RCE en la aplicación de un licenciatario no compromete a ese
licenciatario: compromete **la identidad de todos**.

Como efecto colateral, hoy se expone públicamente **toda** la instancia (con lista blanca de IP),
no solo la base que necesita ser compartida.

### Opción 1 — Separar la instancia *(la preferida a priori)*

Partir el RDS de `ecolors-prod` en dos: una instancia **compartida y pública** con
`EColorsAdminProd`, y una **privada** con las bases de identidad.

- El maestro de la instancia compartida **no existe** para la de identidad → el problema
  desaparece por construcción, sin ingeniería de roles.
- Lo público se reduce a la instancia que debe serlo; identidad vuelve a red privada.
- **El split se deriva solo:** una base es "compartida" si otro client-env la referencia con
  `source` — la misma derivación que ya alimenta `db_public`. Los client-envs que no comparten
  nada (sayer, ulbrika, nonprod) siguen con **una sola instancia**, sin cambios ni costo extra.
- Implementación: instanciar el módulo `database` dos veces en `stacks/foundation`.

**Costo:** una instancia RDS adicional, **solo** en `ecolors-prod`.

### Opción 2 — Usuario dedicado por consumidor *(complementaria)*

Un rol `sayer_app` con `CONNECT` + lectura/escritura únicamente sobre `EColorsAdminProd`.

- Acota qué se puede hacer *dentro* de Admin, no solo a qué instancia se llega.
- Requiere maquinaria nueva: provisionar rol y grants con SQL desde adentro de la VPC, y generar
  y distribuir una contraseña por consumidor.
- **Trampa a no olvidar:** en PostgreSQL, `CONNECT` está concedido a `PUBLIC` por defecto, así que
  hay que hacer `REVOKE CONNECT ... FROM PUBLIC` explícito. Y sin
  **`ALTER DEFAULT PRIVILEGES`**, cada tabla nueva que cree una migración futura de Admin sería
  **invisible** para el licenciatario: la app se rompería *después* de cada deploy de
  `admin-webapi`, no en el momento del cambio de permisos.

Las dos opciones son **complementarias**: la 1 resuelve *a qué datos se llega*; la 2, *qué se
puede hacer con ellos*.

### Qué falta para decidir

1. **Costo** de la instancia RDS adicional en `ecolors-prod` (clase, almacenamiento, y si va
   multi-AZ — ver DT-02).
2. **Impacto en las apps de EColors.** `admin-webapi` pasaría a apuntar a la instancia compartida
   y `authprovider-webapi` a la privada.

   > **Dato que probablemente reduzca mucho la preocupación:** PostgreSQL **no permite consultas
   > entre bases distintas** dentro de una misma instancia (a diferencia de SQL Server). Una
   > conexión habla con **una** base. Por lo tanto, hoy ya es imposible hacer un `JOIN` entre
   > `EColorsAdminProd` y las de identidad. Separarlas en instancias distintas **no rompe nada
   > que hoy funcione**, salvo que se esté usando `dblink` o `postgres_fdw`.
   >
   > **A verificar:** que ninguna app use `dblink` / `postgres_fdw` entre esas bases.

3. **Si conviene aplicar también la opción 2** o alcanza con la 1 por ahora.

### Mientras tanto

Mitigación disponible sin cambios de infraestructura: mantener la lista blanca de IP lo más
estrecha posible y tratar las credenciales del RDS compartido como material sensible de máxima
criticidad (rotación planificada, auditoría de acceso).

---

## DT-02 — Bases de datos en una sola zona de disponibilidad · `ABIERTO` · Riesgo medio

`db_multi_az = false` por defecto. La caída de una zona deja sin base al client-env.

**Camino:** activar `db_multi_az = true` en los client-envs de producción. Es la mejora de
disponibilidad con mejor relación costo/beneficio.

**Qué falta:** el costo (multi-AZ aproximadamente duplica el costo de la instancia) y decidir si
aplica a los cuatro client-envs o solo a producción. Se cruza con DT-01: si se separan las
instancias, hay que decidir multi-AZ para cada una.

---

## DT-03 — Un solo NAT Gateway por VPC · `ABIERTO` · Riesgo medio

Punto único de falla: si cae su zona, el client-env pierde salida a internet — y con ella, el
acceso de `sayer`/`ulbrika` a la base compartida de EColors.

**Caminos:** un NAT por zona (más costo fijo), o reducir la dependencia de internet con **VPC
Endpoints** (el *gateway* de S3 es **gratis** y cubre buena parte del tráfico, ya que las capas de
imágenes de ECR viven en S3).

**Nota de costos ya verificada:** el NAT se cobra **por VPC**, y la cantidad de VPCs la determina
la cantidad de client-envs, **no** de cuentas AWS. Separar `ecolors-prod` y `ecolors-nonprod` en
cuentas distintas **no agregó ningún NAT**, y volver a unirlas **no ahorraría nada**. Solo
ahorraría unir las **VPCs**, lo cual pondría cargas de nonprod en la misma red que los datos de
producción — mal negocio (ver DT-01).

---

## DT-04 — Dependencia total en `ecolors-prod` sin contingencia · `ABIERTO` · Riesgo alto

`ecolors-prod` no es un client-env más: es infraestructura compartida. Dos cosas dependen de ella
para **todos** los licenciatarios:

- la base `EColorsAdminProd` (datos), y
- el **proveedor de identidad** (login).

Si cae, **nadie puede loguearse en ningún licenciatario**, aunque su propia infraestructura esté
sana.

**Qué falta:** definir objetivos de disponibilidad para esta pieza y tratarla con un estándar más
alto que al resto (multi-AZ, monitoreo dedicado, plan de contingencia del login).

---

## DT-05 — Sin observabilidad definida · `ABIERTO` · Riesgo medio

No hay paneles, alarmas ni trazas distribuidas. Los registros van a CloudWatch por defecto, sin
retención ni alertas configuradas. En la práctica: **nadie se entera de un incidente hasta que lo
reporta un usuario.**

**Qué falta:** definir métricas mínimas (salud de App Runner, conexiones y CPU de RDS, errores
5xx, latencia), retención de logs y a dónde notifican las alarmas. Es el contenido previsto del
documento 06 de la serie de arquitectura.

---

## DT-06 — Sin estrategia de recuperación ante desastres · `ABIERTO` · Riesgo medio

Hay copias automáticas de 7 días, pero **no hay restauración probada** ni objetivos definidos de
tiempo (RTO) y punto (RPO) de recuperación. Una copia que nunca se restauró es una hipótesis, no
un respaldo.

**Qué falta:** definir RTO/RPO por client-env y ejecutar una restauración de prueba.

---

## DT-07 — Latencia para usuarios de Uruguay · `ABIERTO` · Riesgo bajo-medio

Todo está en `us-east-1`. Para México (Sayer) el viaje es tolerable; para **Uruguay (Ulbrika)
ronda los 120–160 ms por llamada a la API**, que no pasa por CDN.

Además, el CDN usa `PriceClass_100`, que **excluye Sudamérica**: el frontend de Ulbrika se sirve
desde bordes de EE.UU. (México sí entra en el grupo norteamericano, así que Sayer está bien).

**Caminos:**
- Rápido y acotado: `PriceClass_All` para el frontend de Ulbrika.
- Para la API: **CloudFront delante del backend**, para que el establecimiento de conexión (TCP +
  TLS, varios viajes) termine en un borde cercano y solo el request viaje el tramo largo por la
  red troncal de AWS.

**Lo que NO conviene:** mover a Ulbrika a `sa-east-1`. Dos frenos — App Runner podría no estar
disponible allí (verificar), y sobre todo **`EColorsAdminProd` vive en `us-east-1`**: se ganarían
~120 ms en el request del usuario pero se pagarían ~120 ms **en cada consulta a Admin**, que
suelen ser secuenciales. El resultado neto puede ser peor.

> **Consecuencia arquitectónica a tener presente:** la base compartida (ADR 0007) **ancla
> geográficamente a todos los licenciatarios** a la región donde vive.

**Qué falta:** **medir** la latencia real desde Uruguay antes de construir nada. Optimizar sin
medir es apostar.

---

## DT-09 — Migración desde ECS+ALB · `ABIERTO` · Riesgo alto

Decisión tomada: `web-api-infra` (App Runner) **reemplaza** el diseño ECS+ALB documentado, que
**está desplegado y en uso**. La migración es desplegar la nueva al lado y deprecar la vieja.

- **El punto crítico es el DNS** (colisión de nombres) — ver [`02-dns.md`](./arquitectura/02-dns.md) §2.
- **Ajuste de código pendiente:** durante la convivencia, la zona autoritativa sigue siendo la
  central vieja. Para el cutover por registro (sin delegar todo de golpe), los stacks de
  service/frontend tienen que poder **escribir en una zona externa**. El módulo `dns` ya acepta
  `zone_id` externo; falta exponerlo por client-env en la factory.
- **Delegación NS automática:** ✅ resuelto — la foundation escribe sus NS en la zona padre
  cross-account (rol `dns-delegation` en `stacks/management` + provider `aws.dns`). Requiere setup único.
- **Falta un ADR** que registre *por qué* App Runner en vez de ECS+ALB.

## DT-10 — Dominios propios de cliente · `ABIERTO` · Riesgo bajo (futuro)

Requisito futuro: `ulbrika.shopping.com` → nuestro FE, además de `ulbrika.ecolors.app`. Diseño en
[`02-dns.md`](./arquitectura/02-dns.md) §3. Falta implementar en el módulo `frontend` el caso
"dominio externo" (SAN en el cert + alternate domain en CloudFront + instrucción de los CNAME/TXT
que debe crear el cliente en SU DNS, que no controlamos).

## DT-11 — Endurecer OIDC y sumar el rol de GitHub · `ABIERTO` · Riesgo medio

- **`sub` de `tfc-deploy` demasiado amplio:** hoy permite cualquier workspace de la org `ColorLabs`.
  Restringir por **proyecto de TFC** (asignando proyecto a los workspaces en la factory) o vía
  `tfc_allowed_subs`. Ver [`03-identidad-y-gobierno.md`](./arquitectura/03-identidad-y-gobierno.md) §2.6.
- ~~**Falta el rol OIDC de GitHub Actions**~~ · `RESUELTO`: implementado como `github-deploy`
  (`modules/github-deploy-role`, instanciado por `stacks/foundation`). Push a ECR acotado a los
  repos de la foundation (sin `CreateRepository`), `s3 sync` del FE acotado a sus buckets, e
  invalidación de CloudFront. Trust por repo + `main`/tags, con la lista de repos armada por la
  factory desde `github_repo` de cada backend/frontend. Ejemplos en `examples/app-repo/`.
- **Tags de gobierno faltantes:** agregar `Owner`, `CostCenter`, `Criticality` a `default_tags`.

## DT-12 — Disaster recovery con ARC (us-east-1 + us-east-2) · `ABIERTO` · Riesgo medio (futuro)

Objetivo a futuro: **AWS Application Recovery Controller (ARC)** con presencia en `us-east-1` y
`us-east-2` para recuperación ante caída de región. **Se aborda después** de alinear la migración
ECS→App Runner. Se cruza con DT-02 (multi-AZ) y con la región por client-env ya implementada.

## DT-13 — Migración de la zona `ecolors.app` a la cuenta infrastructure · `ABIERTO` · Riesgo medio

El DNS compartido se movió a `stacks/infrastructure` (cuenta `infrastructure`), pero la zona
`ecolors.app` **hoy sigue en la cuenta management** (`Z04978981S0KQM044JRJY`). Una hosted zone **no
se puede mover** entre cuentas → crear una nueva en infra, **copiar los registros** y **re-delegar
en GoDaddy**. Procedimiento paso a paso en
**[`runbook-migracion-dns.md`](./runbook-migracion-dns.md)**. Además la org ahora se **gestiona** en
Terraform (`aws_organizations_organization`) → requiere `terraform import` una vez.

## DT-14 — Mover el registrador del dominio a AWS (sacar GoDaddy) · `ABIERTO` · Riesgo bajo (futuro)

GoDaddy es hoy **solo el registrador** de `ecolors.app` (el DNS ya lo maneja Route 53). Se puede
consolidar transfiriendo el registro a **Route 53 Domains** (cuenta `infrastructure`), lo que
**elimina el único paso DNS manual/externo** que queda (delegar en GoDaddy) — pasaría a
gestionarse por Terraform con `aws_route53domains_registered_domain`.

Diseño y caveats completos en [`02-dns.md` §3-bis](./arquitectura/02-dns.md). Verificar primero:
- **¿`.app` es transferible a Route 53 Domains?** (no todos los TLDs lo son).
- Regla de 60 días, código de autorización (EPP) de GoDaddy, proceso de 5–7 días, costo de la
  renovación incluida.

La transferencia en sí es manual (una vez); después se gestiona por Terraform. Bajo riesgo, alto
orden — se hace cuando haya tiempo.

## DT-08 — Confirmaciones pendientes del modelo · `ABIERTO` · Riesgo bajo

- **Nombres de las bases de identidad**: `EColorsIdentityProviderProd` / `...Dev` fueron elegidos
  al modelar; confirmar los reales.
- **`price_class` no está expuesto** por frontend en el factory (hoy es fijo por stack). Se
  necesita para DT-07.
- ~~**`aws_region` es global**, no por client-env.~~ → Ya no aplica: la región se fijó a `us-east-1`
  en el provider de cada stack y dejó de ser una variable (el ahorro por región resultó un mito). Si
  algún día se necesita multi-región, es para DR (DT-12) y se hace con providers aliased, no con un
  string por client-env.
