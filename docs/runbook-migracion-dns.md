# Runbook — migrar la zona `ecolors.app` a la cuenta infrastructure (DT-13)

> Mover la hosted zone `ecolors.app` de la cuenta **management** (`Z04978981S0KQM044JRJY`) a la
> cuenta **infrastructure**. Una hosted zone **no se puede mover** entre cuentas → se crea una nueva
> y se hace cutover. Riesgo concentrado en un solo momento (el cambio de name servers).
>
> **Principio de seguridad:** si ambas zonas tienen **los mismos registros**, la propagación del
> cambio de NS es **transparente** — durante la ventana, cualquier resolver (vieja o nueva) responde
> igual. El riesgo aparece solo si los registros **difieren** entre las dos zonas.

Leyenda: 🖐️ manual/consola · 🤖 terraform · 🧰 CLI/script · ⏳ espera.

---

## Fase 0 — Preparación (días antes, sin impacto)

| # | Paso | Tipo |
|---|---|---|
| 0.1 | Aplicar `stacks/infrastructure` → crea la zona `ecolors.app` **nueva y vacía** en la cuenta infra (name servers nuevos) + el rol `dns-delegation`. Anotar el output `parent_zone_name_servers` | 🤖 |
| 0.2 | **Inventariar** la zona vieja: `aws route53 list-resource-record-sets --hosted-zone-id Z04978981S0KQM044JRJY` (en la cuenta management). Revisar TODO lo que hay | 🧰 |
| 0.3 | **Bajar el TTL** de los registros de la zona vieja (ej. a 60s) unos días antes, para que las cachés expiren rápido y el rollback sea veloz | 🧰 |

---

## Fase 1 — Copiar los registros a la zona nueva

| # | Paso | Tipo |
|---|---|---|
| 1.1 | Exportar los registros de la zona vieja **excluyendo el SOA y los NS del apex** (esos son propios de cada zona, autogenerados — NO se copian) | 🧰 |
| 1.2 | Importar todo en la zona nueva. Herramienta recomendada: **`cli53`** (`cli53 export ecolors.app` en una cuenta, `cli53 import` en la otra), o un script con `change-resource-record-sets` en batch | 🧰 |
| 1.3 | **Incluir sí o sí**: los registros de validación de ACM (`_acme-challenge` / CNAME) — si faltan, se rompen las renovaciones de certificados. Y las **delegaciones NS de los subdominios** existentes (sayer/ulbrika/prod/nonprod), salvo que ya las esté escribiendo el factory en la zona nueva | 🧰 |
| 1.4 | Verificar que ambas zonas tienen registros **idénticos**: `dig @<NS-viejo> <nombre>` vs `dig @<NS-nuevo> <nombre>` para cada registro clave | 🧰 |

---

## Fase 2 — Cutover (el momento delicado)

| # | Paso | Tipo |
|---|---|---|
| 2.1 | **Congelar** cambios de DNS (o aplicar cualquier cambio en LAS DOS zonas hasta terminar) | 🖐️ |
| 2.2 | En GoDaddy, cambiar los name servers de `ecolors.app` a los de la zona **nueva** (output de 0.1) | 🖐️ |
| 2.3 | Esperar la propagación. El TTL de los NS lo fija el registro del TLD (`.app`), suele ser horas a ~2 días. Como ambas zonas son idénticas, **no hay corte** durante este tiempo | ⏳ |
| 2.4 | Verificar contra internet: `dig NS ecolors.app` debe devolver los NS nuevos; `dig api.sayer.ecolors.app` (etc.) debe seguir resolviendo | 🧰 |

---

## Fase 3 — Apuntar el factory y limpiar

| # | Paso | Tipo |
|---|---|---|
| 3.1 | En `factory/clients.auto.tfvars`: `dns_parent_account_id` = cuenta infra, `dns_parent_zone_id` = zone id nuevo. Aplicar factory → las foundations delegan en la zona nueva | 🤖 |
| 3.2 | Confirmar por unos días que todo resuelve bien contra la zona nueva | ⏳ |
| 3.3 | **Borrar la zona vieja** en la cuenta management (recién cuando estés seguro) | 🖐️🧰 |

---

## Qué hace Terraform y qué no

- **Terraform** crea/gestiona la zona **nueva** (`stacks/infrastructure`) y el rol de delegación, y
  apunta el factory (3.1). La zona vieja **no** la gestiona Terraform.
- **La copia masiva de registros NO se hace por Terraform** (no querés escribir a mano cada registro
  en HCL, ni la zona vieja está en el estado). Es una operación de **CLI/script** (`cli53` o
  `change-resource-record-sets`).

## Entrelazado con la migración ECS → App Runner

La zona vieja hoy sirve la infra vieja (ECS+ALB). Recomendación para **desacoplar riesgos**:

1. **Primero** mover la zona con registros **idénticos** (Fases 0–2) → cero cambio funcional, solo
   cambia de cuenta.
2. **Después**, dentro de la zona nueva, hacer el cutover de la arquitectura (apuntar cada subdominio
   de ALB a App Runner) **de a un registro**, con TTL bajo, como en `02-dns.md` §2.

Hacer las dos cosas juntas (mover zona + cambiar a App Runner) en un solo paso es el escenario más
riesgoso — evitarlo.

## Nota sobre DT-14

Si además vas a mover el **registrador** a Route 53 Domains (DT-14), el paso 2.2 (cambiar NS en
GoDaddy) se reemplaza por gestionar los NS con `aws_route53domains_registered_domain`. Conviene
hacer **primero** la migración de la zona (este runbook) y **después** la del registrador.
