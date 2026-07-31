# 0008 — Estándar de OUs: environment-first

**Status:** Accepted

## Contexto

La organización creció sin un estándar: OUs por cliente (`EColors`, `Sayer`, `Ulbrika`) con las
cuentas planas adentro, nombres de cuenta inconsistentes (`ecolors-nonprod`, `EColors-Prod`,
`sayer.prod`), tres dominios de email y una cuenta personal colada. Al recrear todas las cuentas
para la arquitectura nueva (App Runner, ADR 0002), es el momento de fijar un estándar.

**Principio:** las OUs existen para aplicar **SCPs (políticas)**. Deben agrupar cuentas que
comparten guardrails. El aislamiento entre clientes **no** es tarea de la OU — se logra con
**cuentas separadas** (ADR 0001). Por eso las OUs se organizan por lo que comparte política: el
**ambiente**.

Con OUs por cliente, prod y nonprod quedan como hermanas bajo cada cliente, y **no se puede
aplicar "prod es más estricto" de forma uniforme** — habría que pegar la SCP cuenta por cuenta.

## Decisión

**Environment-first**, con OUs funcionales:

```
Root
├── Security         (a futuro: log-archive + auditoría)
├── Infrastructure   (a futuro: DNS / red compartida)
├── Workloads
│   ├── Prod         → SCP de prod (deny root, deny borrar CloudTrail/Config, deny regiones)
│   └── NonProd      → SCP de nonprod (bloquear instancias caras, bloquear regiones)
└── Suspended        → SCP restrictiva; cuentas en decomisión
```

- **Cuentas**: `<client>-<env>` (ej. `sayer-prod`, `ecolors-nonprod`), bajo `Workloads/<env>`.
- **Email**: único por cuenta, un solo dominio, patrón `aws-<client>-<env>@<dominio>`.
- **Tenant**: se rastrea con el **tag `Tenant`** + Cost Explorer, no con el árbol de OUs.
- **SCPs**: una por OU de ambiente cubre a todos los clientes de ese ambiente.

## Consecuencias

**A favor.**
- Una SCP por ambiente aplica a todos los clientes → guardrails uniformes, sin olvidos.
- Escala: cliente nuevo = cuentas en `Workloads/Prod|NonProd`, sin OU nueva por cliente.
- `Suspended` da un lugar natural para las cuentas viejas mientras mueren en la migración.
- Marco listo (`Security`, `Infrastructure`) para cuando se agreguen esas cuentas.

**En contra (aceptado).**
- Se pierde el agrupamiento visual por cliente en el árbol de OUs. Se recupera con el tag
  `Tenant`.
- No permite SCPs **distintas por licenciatario**. Si algún día un cliente necesita guardrails
  propios, se resuelve con una OU específica o un permission boundary, sin cambiar el modelo.

**Migración.** Las OUs viejas (`EColors`, `Sayer`, `Ulbrika`) y sus cuentas ECS+ALB **no** las
gestiona Terraform. Se decomisionan a mano: mover las cuentas viejas a `Suspended`, cerrarlas, y
borrar las OUs por cliente cuando queden vacías.

## Implementación

`stacks/management` crea las OUs funcionales y coloca las cuentas vendidas en `Workloads/<env>`
(`workload_environments` mapea el slug del ambiente al nombre de la OU). Ver
`docs/arquitectura/03-identidad-y-gobierno.md`.
