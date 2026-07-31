# Modelo de costos

> **Complemento del documento 01.** Estima el gasto mensual por cliente y ambiente a partir del
> inventario real declarado en `factory/clients.auto.tfvars`.

---

## 0. Advertencia sobre la precisión (leer antes de usar estos números)

Estas cifras **son estimaciones, no una cotización**. Concretamente:

- Son **precios de lista de `us-east-1`** según el conocimiento con el que se armó el modelo.
  **Los precios de AWS cambian.** Antes de usar esto para presupuestar o negociar, verificalo con
  la [Calculadora de precios de AWS](https://calculator.aws/).
- **No incluyen** impuestos, planes de soporte, ni descuentos por volumen o compromiso
  (*Savings Plans*, *Reserved Instances*).
- **No incluyen la capa gratuita**, que puede reducir bastante el primer año.
- Los componentes **variables** (tráfico, peticiones, minutos de build) se estiman con supuestos
  explícitos, porque **no hay datos de uso real todavía**. Son los que más se pueden desviar.

**Lo que sí es exacto:** el *inventario* de recursos, porque se deriva de la configuración.

---

## 1. Inventario derivado de la configuración

| client-env | Backends | Frontends | Bases locales | Instancias RDS |
|---|---:|---:|---:|---:|
| `sayer-prod` | 1 | 1 | 1 | 1 |
| `ulbrika-prod` | 1 | 1 | 1 | 1 |
| `ecolors-prod` | 2 | 2 | 3 | 1 |
| `ecolors-nonprod` | 5 | 4 | 6 | 1 |
| **Total** | **9** | **8** | **11** | **4** |

Cada client-env tiene además, por diseño: 1 VPC, 1 NAT Gateway, 1 bastión, 1 zona DNS, 1 secreto
maestro, y un repositorio de imágenes por backend.

---

## 2. Precios unitarios usados

| Recurso | Precio de lista aprox. (us-east-1) | Notas |
|---|---|---|
| NAT Gateway | $0,045 / hora + $0,045 / GB procesado | El costo por hora corre **siempre** |
| App Runner — memoria aprovisionada | $0,007 / GB-hora | Se paga **aunque no haya tráfico** |
| App Runner — vCPU activa | $0,064 / vCPU-hora | Solo mientras procesa peticiones |
| RDS `db.t4g.micro` | $0,016 / hora | Instancia única (sin multi-AZ) |
| RDS almacenamiento `gp3` | $0,115 / GB-mes | Arranca en 20 GB |
| EC2 `t4g.nano` (bastión) | $0,0042 / hora | |
| EBS `gp3` (bastión, 8 GB) | $0,08 / GB-mes | |
| Zona alojada Route 53 | $0,50 / mes | + $0,40 por millón de consultas |
| Secrets Manager | $0,40 / secreto-mes | 1 por client-env (credencial maestra) |
| ECR | $0,10 / GB-mes | |
| CloudFront | $0,085 / GB salida + peticiones | Sin costo fijo |
| S3 | $0,023 / GB-mes | Un SPA pesa muy poco |
| CodeBuild `general1.small` | $0,005 / minuto de build | Solo migraciones |
| ACM, SSM Parameter Store (estándar), VPC | **Gratis** | |

**Supuestos de uso** (los que más pueden desviarse):
- App Runner con **1 instancia aprovisionada** de 1 vCPU / 2 GB (los valores por defecto).
- Escenario *en reposo*: ~0 % de tiempo de vCPU activa. Escenario *con carga*: **10 %**.
- Tráfico bajo de CDN y poco almacenamiento de imágenes y objetos.
- 730 horas por mes.

---

## 3. Costo fijo común a cada client-env

Corre 24×7 sin importar el tráfico, y es igual para los cuatro:

| Componente | Cálculo | USD/mes |
|---|---|---:|
| NAT Gateway | $0,045 × 730 | **32,85** |
| RDS `db.t4g.micro` | $0,016 × 730 | 11,68 |
| RDS almacenamiento (20 GB) | $0,115 × 20 | 2,30 |
| Bastión `t4g.nano` | $0,0042 × 730 | 3,07 |
| Bastión EBS (8 GB) | $0,08 × 8 | 0,64 |
| Zona Route 53 | fijo | 0,50 |
| Secrets Manager | 1 secreto | 0,40 |
| **Base fija por client-env** | | **≈ 51,44** |

---

## 4. Costo por cliente y ambiente

### En reposo (sin tráfico; solo lo que corre siempre)

| client-env | Base fija | App Runner | CDN + S3 | ECR | **Total/mes** |
|---|---:|---:|---:|---:|---:|
| `sayer-prod` | 51,44 | 10,22 (×1) | ~0,75 | ~0,15 | **≈ 62,6** |
| `ulbrika-prod` | 51,44 | 10,22 (×1) | ~0,75 | ~0,15 | **≈ 62,6** |
| `ecolors-prod` | 51,44 | 20,44 (×2) | ~1,50 | ~0,30 | **≈ 73,7** |
| `ecolors-nonprod` | 51,44 | 51,10 (×5) | ~3,00 | ~0,75 | **≈ 106,3** |
| **Total** | **205,8** | **92,0** | **~6,0** | **~1,4** | **≈ 305 USD/mes** |

### Con carga moderada (10 % de tiempo de vCPU activa)

Cada backend suma ≈ $4,67/mes (1 vCPU × $0,064 × 73 h).

| client-env | En reposo | + vCPU activa | **Total/mes** |
|---|---:|---:|---:|
| `sayer-prod` | 62,6 | +4,7 | **≈ 67,3** |
| `ulbrika-prod` | 62,6 | +4,7 | **≈ 67,3** |
| `ecolors-prod` | 73,7 | +9,3 | **≈ 83,0** |
| `ecolors-nonprod` | 106,3 | +23,4 | **≈ 129,7** |
| **Total** | 305 | +42 | **≈ 347 USD/mes** |

*No incluye tráfico de CDN ni datos procesados por el NAT, que dependen del uso real.*

---

## 5. Distribución del gasto y hallazgos

### En reposo

| Concepto | USD/mes | % del total |
|---|---:|---:|
| **NAT Gateway** (4) | 131,4 | **43 %** |
| **App Runner** (9) | 92,0 | 30 % |
| RDS (4) | 55,9 | 18 % |
| Bastión (4) | 14,8 | 5 % |
| CDN, S3, ECR, DNS, secretos | ~11,0 | 4 % |

### Tres hallazgos

**1. El NAT Gateway es la mayor línea de gasto en reposo — 43 %.**
Corrige lo que decía el documento 01: yo había afirmado que App Runner dominaba. Con los números
puestos, **en reposo el NAT domina** ($131 contra $92). Recién con carga sostenida App Runner lo
alcanza (~$134 contra $131 al 10 % de actividad). Tu instinto inicial sobre el NAT era correcto.

**2. El ambiente de NO producción es el más caro de los cuatro.**
`ecolors-nonprod` cuesta ≈ $106/mes, **más que `ecolors-prod`** (≈ $74) y casi el doble que cada
licenciatario. La razón es simple: tiene 5 backends contra 2. Y usa exactamente el **mismo
dimensionamiento que producción** (1 vCPU / 2 GB por servicio, RDS igual), lo cual casi nunca se
justifica en un ambiente de pruebas.

**3. Los licenciatarios cuestan casi lo mismo que la plataforma.**
Cada licenciatario nuevo agrega ≈ **$63/mes de piso**, de los cuales **$51 son costo fijo de
infraestructura** (NAT + RDS + bastión) independiente de cuánto se use. Es el precio explícito del
aislamiento por cliente (ADR 0001). Vale tenerlo presente al fijar el precio del licenciamiento.

---

## 6. Palancas de optimización, ordenadas por impacto

| # | Palanca | Ahorro estimado | Costo de aplicarla |
|---|---|---:|---|
| 1 | **Apagar el NAT donde no haga falta** (`enable_nat = false`) | hasta **$66/mes** (2 de 4) | Requiere que nada necesite salida a internet |
| 2 | **Achicar App Runner en nonprod** (0,5 vCPU / 1 GB) | ≈ **$26/mes** | Ninguno; es un ambiente de pruebas |
| 3 | **Pausar nonprod fuera de horario** | ≈ **$35–50/mes** | App Runner permite pausar; RDS se puede detener hasta 7 días |
| 4 | **Bastión bajo demanda** en vez de siempre encendido | ≈ **$11/mes** (3 de 4) | Hay que levantarlo cuando se necesita |
| 5 | **VPC Endpoint de S3** (gateway) | reduce GB procesados por el NAT | **Gratis**; las capas de ECR viven en S3 |

**Sobre la palanca 1:** el NAT se cobra **por VPC**, y la cantidad de VPCs la determina la cantidad
de client-envs, **no** de cuentas AWS. Separar `ecolors-prod` y `ecolors-nonprod` en cuentas
distintas **no agregó ningún NAT**, y unirlas **no ahorraría nada**. La pregunta correcta por cada
client-env es: *¿algo acá necesita salir a internet?* Sayer y Ulbrika **sí** (van al RDS público de
EColors). Los de EColors quizá no, salvo por CodeBuild bajando paquetes de NuGet.

---

## 7. Costo de las deudas técnicas pendientes

Números para decidir los ítems de [`deuda-tecnica.md`](../deuda-tecnica.md):

| Deuda | Cambio | Costo adicional |
|---|---|---:|
| **`DT-01`** — aislar el proveedor de identidad | +1 instancia RDS `db.t4g.micro` + 20 GB, **solo en `ecolors-prod`** | **≈ $14/mes** |
| `DT-02` — alta disponibilidad de bases | Multi-AZ ≈ duplica el costo de instancia | ≈ **+$12/mes por client-env** |
| `DT-03` — NAT redundante | Un NAT por zona (2 zonas) | ≈ **+$33/mes por client-env** |
| `DT-07` — latencia Uruguay | `PriceClass_All` en el CDN de Ulbrika | Marginal con tráfico bajo |

> **Nota sobre `DT-01`:** aislar las bases de identidad de las cuentas de terceros cuesta
> **≈ $14 por mes** — alrededor del **4 % del gasto total**. Es la mitigación de riesgo alto más
> barata de toda la lista. Verificá el número con la calculadora, pero el orden de magnitud
> sugiere que la decisión no debería trabarse por costo.

---

## 7-bis. Auditoría de desperdicio (verificada contra el código, 2026-07)

Lo que está prendido **sin necesidad clara** o mal dimensionado. Ordenado por ahorro estimado.

### 🔴 Bastión encendido 24/7 — desperdicio puro

`enable_bastion = true` por defecto crea un `t4g.nano` **siempre encendido** en cada client-env,
para un uso **ocasional** (túnel SSM a la base para admin). Está prendido las 730 horas del mes
aunque no lo uses.
- **Ahorro:** ~$3/mes por client-env (× 4 = ~$12/mes). Chico en plata, pero es 100% ocioso.
- **Cómo:** apagar la instancia cuando no se usa (o `enable_bastion = false` y levantarla on-demand
  para las sesiones de admin). El costo real de un bastión debería ser casi cero.

### 🔴 NAT Gateway — la línea más grande; ¿todos lo necesitan?

`enable_nat = true` por defecto → un NAT **por client-env** (~$33/mes fijo cada uno + datos). Es el
**43% del costo en reposo**. Pregunta por client-env: *¿algo acá necesita salir a internet?*
- **sayer / ulbrika:** SÍ — su backend llega a la base `Admin` pública de ecolors por internet.
- **ecolors-prod / nonprod:** sus apps llegan a **su propia RDS por red privada** (no necesitan
  NAT para eso). Solo lo necesitarían si (a) las apps llaman APIs externas, o (b) las migraciones de
  CodeBuild bajan paquetes de NuGet público.
- **Ahorro:** hasta ~$33/mes por cada client-env donde se pueda apagar. **Verificar caso por caso.**

### 🟠 Ningún VPC endpoint — oportunidad, no problema

**No hay ningún VPC endpoint creado** (verificado). Así que tu duda de "muchos endpoints" no aplica
— tenés cero, no hay desperdicio ahí. Al revés: **agregar el gateway endpoint de S3 es GRATIS** y
reduce los **datos procesados por el NAT** (las capas de imágenes de ECR viven en S3, y el tráfico a
S3 pasaría por el endpoint en vez del NAT). Los endpoints de **interfaz** (ECR API, SSM, Logs) SÍ
cuestan (~$0.01/hora por AZ cada uno) — hay que hacer la cuenta antes de agregarlos; el de S3 es el
único claramente gratis y positivo.

### 🟠 App Runner en NonProd sobredimensionado y siempre activo

Los 5 servicios de nonprod usan el mismo dimensionamiento que prod (1 vCPU / 2 GB) y App Runner
**cobra la memoria aprovisionada aunque no haya tráfico**.
- **Ahorro:** bajar nonprod a 0.5 vCPU / 1 GB (~$26/mes), y/o **pausar** los servicios de nonprod
  fuera de horario laboral (App Runner permite pausar).

### 🟡 Logs de CloudWatch sin retención — desperdicio lento

**No se setea `retention_in_days` en ningún log group** (verificado) → los logs de App Runner y
CodeBuild se guardan **para siempre**, acumulando costo mes a mes.
- **Ahorro:** crece con el tiempo; hoy chico, en un año es real.
- **Cómo:** setear retención por ambiente (ej. 30 días nonprod, 90 prod). Cambio de una línea por
  log group.

### 🟡 Menores

- **Secrets Manager:** 1 secreto master por client-env (~$0.40/mes cada uno). Se podría usar
  Parameter Store SecureString también para el master (gratis), pero es marginal.
- **Bases en una sola AZ:** *no* es desperdicio — es un ahorro (Multi-AZ costaría más). Pero es una
  deuda de disponibilidad (DT-02), no de costo. No lo apagues "para ahorrar" sin entender el trade-off.

### Resumen del ahorro potencial (en reposo, orden de magnitud)

| Acción | Ahorro/mes aprox. | Riesgo |
|---|---|---|
| Apagar NAT donde no se necesita (2 de 4) | hasta ~$66 | Requiere confirmar que nada sale a internet |
| Achicar App Runner nonprod | ~$26 | Ninguno (es dev/qa) |
| Pausar nonprod fuera de horario | ~$35–50 | Ninguno |
| Bastión on-demand (3 de 4) | ~$11 | Levantarlo cuando haga falta |
| Gateway endpoint de S3 | reduce datos del NAT | Gratis |
| Retención de logs | crece con el tiempo | Ninguno |

### Estado de implementación (2026-07)

**Ya implementado (ahorros seguros):**
- ✅ **Bastión on-demand**: `enable_bastion = false` por defecto. Se prende para una sesión de admin
  y se apaga. Las apps/migraciones llegan a la RDS sin él.
- ✅ **Gateway endpoint de S3**: creado por defecto en cada VPC (`enable_s3_endpoint`). Gratis;
  desvía a S3/ECR del NAT.
- ✅ **App Runner nonprod más chico**: `ecolors-nonprod` en 0.5 vCPU / 1 GB (`service_cpu`/
  `service_memory` por client-env en el factory).

- ✅ **Pausar nonprod en la madrugada**: EventBridge Scheduler pausa/reanuda cada backend
  (`service_pause` por client-env; `ecolors-nonprod` pausa 02:00–07:00). App Runner no cobra
  instancias aprovisionadas mientras está pausado.

**NO aplica / pendiente:**
- ❌ **Apagar el NAT**: descartado. **Todos los ambientes** integran con servicios externos (pagos,
  envíos), así que **todos necesitan salida a internet**. El NAT se queda en todos los client-envs.
- ⏳ **Retención de logs**: los logs de App Runner van a grupos con id autogenerado, así que **no se
  puede setear retención por Terraform directo** — necesita un Lambda que la aplique a los grupos
  nuevos (EventBridge on-create). Queda como follow-up. Los de CodeBuild sí se podrían acotar.

## 8. Cómo mantener esto actualizado

El **inventario** (sección 1) se deriva de `clients.auto.tfvars`: cada cliente, backend o frontend
nuevo lo cambia. Los **precios** (sección 2) hay que revisarlos periódicamente contra AWS.

Una vez que haya tráfico real, lo más valioso es reemplazar los supuestos por datos: activar
**AWS Cost Explorer** con desglose por cuenta (que ya es por cliente, gracias al aislamiento) y
por etiqueta `Client` / `Environment`, que los stacks ya aplican con `default_tags`.
