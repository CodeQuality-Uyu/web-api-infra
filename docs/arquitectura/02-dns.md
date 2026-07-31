# 02 — DNS: modelo, diferencias y migración

> **Documento 2 de la serie de arquitectura.** Explica cómo se resuelven los nombres de dominio
> en la plataforma nueva, en qué se diferencia del modelo documentado (ECS+ALB), **el problema de
> colisión durante la migración** (que es el riesgo real de convivir las dos infraestructuras), y
> cómo se soportarán a futuro los **dominios propios de cliente** (`ulbrika.shopping.com`).

## 0. Repaso mínimo (sin dar nada por sabido)

- **DNS** traduce un nombre (`api.sayer.ecolors.app`) a un destino técnico (una IP o un recurso
  de AWS). Es el "mapa" que usa el navegador para encontrar el servidor.
- **Hosted zone (zona alojada):** el contenedor donde se administran los registros de un dominio.
  Puede haber **una** zona para todo, o **muchas** (una por subdominio).
- **Delegación NS:** para que una zona funcione, el dominio padre tiene que "delegar" apuntando a
  los *name servers* de la zona hija. Es lo que conecta `ecolors.app` (en el registrador) con una
  zona de Route 53.
- **Registro A/ALIAS:** apunta un nombre a una IP o a un recurso de AWS. **ALIAS** es una
  extensión de Route 53 que funciona incluso en la raíz del dominio (el *apex*).
- **Registro CNAME:** apunta un nombre a **otro nombre**. No se permite en el apex.
- **Certificado (ACM):** habilita `https://`. Se valida creando un registro (TXT o CNAME) en la
  zona; ACM verifica que controlás el dominio y emite el certificado.

---

## 1. Los dos modelos, lado a lado

### Modelo documentado (ECS + ALB) — **una zona central**

```
Registrador (GoDaddy)  ──delegación NS──▶  Route 53: UNA hosted zone  ecolors.app
                                             │
       ┌─────────────────────────────────────┼───────────────────────────────┐
       │ sayer.ecolors.app        (A ALIAS → CloudFront)                       │
       │ tenant1.ecolors.app      (A ALIAS → CloudFront)                       │
       │ authprovider.dev.api.ecolors.app  (A ALIAS → ALB)                     │
       │ authprovider.qa.api.ecolors.app   (A ALIAS → ALB)                     │
       │ *.ecolors.app            (certificado WILDCARD en ACM)                │
       └──────────────────────────────────────────────────────────────────────┘
```

- **Una sola zona** `ecolors.app` contiene *todos* los nombres, de todos los tenants y ambientes.
- Un **certificado wildcard `*.ecolors.app`** cubre todo de una.
- El ambiente va **en el medio** del nombre: `<app>.<env>.api.ecolors.app`.
- Todas las APIs entran por **el mismo ALB**, que decide por *host* a qué servicio mandar.

**Ventaja:** control centralizado, un solo lugar para todo, un solo certificado.
**Costo:** esa zona es un punto único; un error ahí afecta a todos los tenants.

### Modelo construido (App Runner) — **una zona por client-env**

```
Registrador  ──delegación NS (una por cliente)──▶  Route 53 en la CUENTA de cada cliente
   │
   ├─▶ zona  sayer.ecolors.app        (cuenta SAYER)
   │        sayer.ecolors.app          A ALIAS → CloudFront (FE)
   │        api.sayer.ecolors.app      CNAME  → App Runner
   │
   ├─▶ zona  ulbrika.ecolors.app       (cuenta ULBRIKA)
   │
   ├─▶ zona  prod.ecolors.app          (cuenta ECOLORS-PROD)
   │        admin.prod.ecolors.app         A ALIAS → CloudFront
   │        admin.api.prod.ecolors.app     CNAME  → App Runner
   │
   └─▶ zona  nonprod.ecolors.app       (cuenta ECOLORS-NONPROD)
```

- **Una zona por client-env**, y vive **dentro de la cuenta de ese cliente**.
- El certificado se emite **por recurso** (cada App Runner y cada CloudFront tiene el suyo, que
  ACM renueva solo). No hay wildcard.
- El ambiente es la **raíz de la zona**: `<app>.api.<zona>` → `admin.api.prod.ecolors.app`.
- Cada API entra por **su propio** App Runner (no hay ALB compartido).

**Ventaja:** aislamiento total — la zona de un cliente vive en su cuenta; un problema no cruza.
**Costo:** hay que delegar NS una vez por cliente, y hay más zonas que administrar.

### Tabla de diferencias

| Aspecto | Documentado (ECS+ALB) | Construido (App Runner) |
|---|---|---|
| Zonas alojadas | **1** central (`ecolors.app`) | **1 por client-env**, en su cuenta |
| Dónde vive la zona | Cuenta central | Cuenta del cliente |
| Certificado | **Wildcard** `*.ecolors.app` | Uno **por recurso**, DNS-validado |
| Posición del ambiente | En el medio: `app.env.api.ecolors.app` | En la raíz: `app.api.env.ecolors.app` |
| Entrada de las APIs | ALB compartido, ruteo por host | Un App Runner por API |
| Registro del FE | A ALIAS → CloudFront | A ALIAS → CloudFront *(igual)* |
| Ambientes nonprod | dev + qa (dos) | un solo `nonprod` |

> **Decisión tomada:** la plataforma nueva (App Runner, zona por client-env) **reemplaza** al
> modelo ECS+ALB. La migración es *desplegar la nueva al lado y deprecar la vieja*. Por eso este
> documento se concentra en el único punto donde ambas se pisan: **el DNS**.

---

## 2. El problema real de la migración: la colisión de nombres

Mientras ambas infraestructuras coexisten, **las dos quieren responder por los mismos nombres**.
Un registro DNS es un valor único: `admin.api.prod.ecolors.app` apunta al ALB **o** al App Runner,
no a los dos. Si se crea el registro nuevo, deja de resolver el viejo, y viceversa. Ese es el
riesgo que identificaste.

Peor aún: hay un **cambio de forma de zona**. Hoy los nombres viven en la **zona central**
`ecolors.app` (modelo viejo). En el modelo nuevo, `prod.ecolors.app` es **su propia zona** en otra
cuenta. Para que `admin.api.prod.ecolors.app` resuelva contra la cuenta nueva, `ecolors.app` tiene
que **delegar** `prod.ecolors.app` a los name servers de la zona nueva — y en el momento en que se
delega, **todos** los nombres bajo `prod.ecolors.app` dejan de resolverse contra la zona vieja de
golpe. La delegación es un interruptor de todo-o-nada por subdominio.

### Estrategias de convivencia (de menor a mayor riesgo)

**Opción A — Nombres nuevos en paralelo, cutover por registro *(recomendada)*.**
No delegar la zona todavía. En la **zona central existente** (`ecolors.app`), agregar los
registros nuevos apuntando a los recursos de App Runner/CloudFront nuevos, con nombres que **no
coincidan** con los viejos mientras se prueba (ej. `admin.api.prod.ecolors.app` sigue en el ALB;
se prueba contra la URL nativa de App Runner o un nombre temporal `admin-v2.api...`). Cuando la
app nueva está verificada, se **cambia un registro a la vez** para que apunte al recurso nuevo, con
un **TTL bajo** (60 s) puesto *antes* del cambio para poder revertir rápido.
- **Pro:** cutover y rollback por servicio, granular, sin interruptor global.
- **Contra:** requiere administrar los registros del modelo nuevo *desde la zona central vieja*
  durante la transición (nuestros stacks asumen zona propia — ver "Ajuste para la migración").

**Opción B — Delegar por ambiente, con TTL bajo.**
Bajar el TTL de los registros NS de `prod.ecolors.app` con anticipación, verificar que la zona
nueva ya tiene *todos* los registros necesarios, y **delegar** el subdominio completo a la cuenta
nueva. El corte es por ambiente, no por servicio.
- **Pro:** es el estado final deseado; se hace una vez por ambiente.
- **Contra:** mueve *todo* el ambiente de golpe; si falta un registro en la zona nueva, ese
  servicio cae hasta que se agregue.

**Opción C — Peso / failover de Route 53.**
Si durante un tiempo se quiere mandar *parte* del tráfico a cada infraestructura, Route 53 permite
registros con **peso** (ej. 90% viejo / 10% nuevo) o **failover**. Requiere que ambos respondan el
mismo nombre, lo que en zonas separadas es más complejo (health checks + registros alias en ambas).
- **Pro:** migración gradual con validación de tráfico real.
- **Contra:** la más compleja de operar; usar solo si se necesita canary.

### Reglas que aplican a cualquier opción

1. **Bajar el TTL antes, no después.** Un registro con TTL de 300 s tarda hasta 5 minutos en
   revertirse; ponelo en 60 s *días antes* del cutover.
2. **Los certificados nuevos se pueden emitir sin cortar nada.** La validación de ACM usa
   registros TXT/CNAME `_acme-challenge` que **no** colisionan con los registros de tráfico. Se
   pueden emitir todos los certificados nuevos con la infra vieja aún sirviendo.
3. **App Runner valida su dominio por CNAME**, y ese CNAME de validación tampoco pisa el registro
   de tráfico hasta que vos apuntás el nombre final.
4. **Un servicio a la vez.** No migrar `prod` entero en un solo paso salvo que se acepte el riesgo.

### Delegación automática (implementada)

La delegación de cada subdominio de licenciatario **ya no es un paso manual**. El factory resuelve
solo la cuenta y la zona padre desde el remote state (management + infrastructure) — no se pegan
`dns_parent_*` a mano. Con eso, la foundation de cada cliente:

1. crea su propia zona (`sayer.ecolors.app`),
2. **asume el rol `dns-delegation`** en la cuenta que tiene la zona padre (`ecolors.app`),
3. y escribe ahí sus registros **NS** (cross-account, vía un provider `aws.dns`).

El rol `dns-delegation` se crea en [`stacks/management`](../../stacks/management) — la cuenta donde
vive `ecolors.app`. La zona **se referencia por id** (ya existe, no se recrea) y solo se crea el
rol, que confía únicamente en roles `tfc-deploy` **dentro de la organización**
(`aws:PrincipalOrgID`) y solo puede tocar registros **tipo NS** en la zona padre — no puede
secuestrar el apex ni otros registros. Así, un cliente nuevo delega su subdominio solo, sin que
nadie edite la zona central. (La delegación del apex `ecolors.app` en GoDaddy sigue siendo el único
paso DNS manual, y es una sola vez.)

### Ajuste que la migración necesita en el repo

Nuestros stacks asumen que **la zona vive en el foundation del propio cliente** (leen `zone_id` de
ahí). Durante la convivencia, la zona autoritativa sigue siendo la **central vieja**. Para no
forzar la delegación antes de tiempo hay dos caminos:

- **Delegar temprano** (Opción B) y aceptar el interruptor por ambiente — el repo funciona tal
  cual.
- **Escribir los registros en la zona vieja** durante la transición — requiere que el módulo `dns`
  acepte un `zone_id` externo (ya tiene `create_zone`/`zone_id`, así que es viable) y que los
  stacks de servicio/frontend puedan apuntar a esa zona central. Es un cambio acotado, pero hay que
  hacerlo **si** se elige el cutover por registro.

> Esto no está resuelto en el código todavía. Es una decisión de *cómo* migrar que conviene tomar
> antes del primer cutover. Registrado en `deuda-tecnica.md`.

---

## 3. A futuro: dominios propios del cliente (`ulbrika.shopping.com`)

Hoy cada cliente vive bajo `*.ecolors.app`. El requisito futuro es que un cliente pueda usar
**su propio dominio** —por ejemplo `ulbrika.shopping.com`— apuntando al **mismo** frontend, además
de `ulbrika.ecolors.app`. Esto es el "Caso B" que EColors ya tenía documentado.

La diferencia clave: **el DNS de `shopping.com` no lo controla EColors, lo controla el cliente.**
Entonces no se puede delegar ni crear registros ahí desde nuestra cuenta. El patrón es:

```
1. EColors:  agrega ulbrika.shopping.com como Alternate Domain Name (CNAME) en la
             distribución CloudFront del FE de Ulbrika.
2. EColors:  emite/expande el certificado ACM para incluir ese nombre (SAN).
             ACM pide un registro de validación (CNAME _acme-challenge...).
3. CLIENTE:  en el DNS de shopping.com, agrega DOS registros que le pasa EColors:
             - CNAME  _acme-challenge.ulbrika...  → (valor que da ACM)   [valida el cert]
             - CNAME  ulbrika.shopping.com        → dxxxx.cloudfront.net  [manda el tráfico]
4. Listo:    https://ulbrika.shopping.com sirve el mismo SPA, con su propio certificado.
```

Puntos importantes de este modelo:

- **El apex del cliente es un problema aparte.** Si el cliente quiere `shopping.com` pelado (no
  `www.` ni `ulbrika.`), no puede usar CNAME en su apex (misma limitación de siempre). Ahí depende
  de si su proveedor de DNS soporta "CNAME flattening" / ALIAS. Con un subdominio
  (`ulbrika.shopping.com`) no hay problema.
- **Este flujo necesita interacción del cliente** (agregar dos registros). No es
  100% automatizable desde nuestro lado; sí se le puede generar la instrucción exacta.
- **En el modelo nuevo esto encaja bien:** ya emitimos un certificado por frontend y ya usamos
  CloudFront con dominios alternativos. Agregar un dominio de cliente es sumar un SAN + un
  *alternate domain name* + los registros que el cliente debe crear. En el módulo `frontend` esto
  se mapea a los campos `subject_alternative_names` (para el SAN/cert) y a los aliases de la
  distribución.

> No está implementado el flujo completo (falta el manejo de la validación cuando el dominio es
> externo y no está en nuestra Route 53). Es una extensión natural del módulo `frontend` cuando el
> requisito se active. Registrado en `deuda-tecnica.md`.

---

## 3-bis. Registrador: sacar GoDaddy y gestionar el dominio 100% en AWS (deuda, DT-14)

GoDaddy cumple **dos roles distintos**, y uno ya está en AWS:

| Rol | Qué es | Dónde está hoy |
|---|---|---|
| **Registrador** | Dónde está *registrado* `ecolors.app` (a quién se le paga la renovación) | **GoDaddy** |
| **DNS hosting** | Quién *sirve* los registros (name servers autoritativos) | **Route 53** (ya delegado) |

Hoy GoDaddy es **solo el registrador**; el DNS ya lo maneja Route 53. Lo único que hace GoDaddy es
apuntar el dominio a los name servers de Route 53 — el único paso DNS **manual y externo** que
queda en todo el diseño.

**Se puede sacar** transfiriendo el registro a **Amazon Route 53 Domains** (el registrador de AWS).
End state: AWS pasa a ser registrador + DNS, en la cuenta `infrastructure`.

```
Route 53 Domains (registro, cuenta infrastructure)   ← reemplaza a GoDaddy
   └── name servers → zona ecolors.app (misma cuenta)
        └── delegaciones de subdominios ← ya automáticas (dns-delegation)
```

**Lo que se gana:** un solo proveedor, y el paso manual de "delegar en GoDaddy" **desaparece** — con
`aws_route53domains_registered_domain` Terraform mantiene los name servers apuntando a la zona.

**Caveats (verificar antes):**
1. **¿`.app` es transferible a Route 53 Domains?** No todos los TLDs se pueden — verificar la lista
   soportada de AWS. Si no está, se queda GoDaddy (sin drama: el DNS ya está en AWS).
2. La transferencia es un proceso de **5–7 días** (ICANN): desbloquear en GoDaddy, sacar el
   **código de autorización (EPP)**, a veces desactivar WHOIS privacy, aprobar mails.
3. **Regla de 60 días:** no se transfiere si se registró/transfirió hace menos de 60.
4. **Costo:** la transferencia incluye ~1 año de renovación (`.app` ~$14–20/año, verificar).
5. El **DNS no se corta** durante la transferencia (los name servers ya son de Route 53).

**Terraform:** la transferencia en sí **no** se hace por Terraform (operación asíncrona del
registrador, una vez, por consola/CLI). Una vez en Route 53, **sí** se gestiona con
`aws_route53domains_registered_domain` (auto-renovación, lock, name servers). Registrado como
**DT-14**; se hace más adelante.

## 4. Resumen

- **Hoy:** una zona por client-env, en la cuenta del cliente, certificado por recurso. Aísla, pero
  hay que delegar NS por cliente.
- **Migración:** el único punto de fricción con la infra ECS+ALB vieja es el DNS. La colisión se
  maneja con **cutover por registro y TTL bajo**, no con un interruptor global. Los certificados
  nuevos se emiten sin cortar tráfico.
- **Futuro:** dominios propios del cliente vía SAN en el certificado + CNAME que agrega el cliente
  en su DNS. El modelo nuevo lo soporta conceptualmente; falta implementar el caso "dominio
  externo".
