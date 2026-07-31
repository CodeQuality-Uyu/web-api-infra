# Disaster Recovery — hoja de ruta (no implementado)

> **Estado: DOCUMENTADO, NO IMPLEMENTADO.** Este documento captura el análisis y el orden correcto
> para llegar a DR, incluido AWS ARC. Falta definir RTO/RPO antes de construir nada. Registrado en
> `deuda-tecnica.md` (DT-02, DT-04, DT-12).

## 0. Vocabulario mínimo

- **DR (Disaster Recovery):** cómo se recupera el sistema ante una falla grave (una zona, una
  región, un borrado masivo).
- **RTO (Recovery Time Objective):** cuánto tiempo podés estar caído antes de recuperar. "Minutos"
  es caro; "horas" es barato.
- **RPO (Recovery Point Objective):** cuántos datos podés perder (medido en tiempo). "Cero" exige
  replicación síncrona; "última hora" alcanza con backups frecuentes.
- **AZ (zona de disponibilidad):** un datacenter dentro de una región. Varias AZ = tolerancia a la
  caída de un datacenter.
- **Región:** un conjunto de AZ en una geografía (us-east-1 = Virginia, us-east-2 = Ohio).

## 1. Qué es AWS ARC — y qué NO es

**AWS Application Recovery Controller** es un **interruptor de failover confiable**, no la
infraestructura de DR. Tiene dos partes:

- **Routing controls:** switches (tipo circuit breaker) para mover tráfico DNS entre regiones a
  mano, con un cluster de 5 endpoints redundantes que funcionan **aunque una región esté caída**.
- **Readiness checks:** auditan que la región standby esté realmente lista (capacidad, config).

**El malentendido a evitar:** ARC **no crea** tu segunda región ni replica tus datos. Asume que
*ya* tenés la app corriendo en dos regiones y los datos replicados. **Es el último eslabón, no el
primero.** Prender ARC hoy sería un interruptor apuntando a una región vacía.

## 2. El estado actual (por qué ARC es prematuro)

- App Runner en **una sola región** por client-env.
- RDS **single-instance, single-AZ, single-region** (Multi-AZ ni siquiera está prendido — DT-02).
- **Cero replicación cross-region** de datos.

> Aclaración clave: hoy **todo (prod y nonprod) vive en us-east-1** — una sola región, cero DR
> cross-region. DR de prod significaría *prod mismo* en us-east-1 **y** una segunda región (us-east-2
> es la candidata). Tener otro ambiente en otra región no sería DR: sería otro ambiente.

## 3. Las amenazas y su costo

| Amenaza | Probabilidad | Solución | Costo aprox. |
|---|---|---|---|
| **Falla de una AZ** | La más común | RDS **Multi-AZ** | ~+$12/mes por instancia |
| **Borrado / corrupción de datos** | Media | Backups + PITR (ya hay 7 días) | incluido |
| **Caída de región entera** | Rara | Multi-region + ARC | ~**2x** la infra |

La mayoría de las plataformas cubren primero **falla de AZ** (el ~90% de los incidentes reales) y
dejan el failover de región para una madurez posterior.

## 4. DR por capas (el orden correcto)

```
1. Resiliencia de AZ      → RDS Multi-AZ            (barato, alto valor; ya es un toggle db_multi_az)
2. Punto de recuperación  → backups cross-region    (aws_db_instance_automated_backups_replication)
3. Standby cross-region   → read replica / Aurora Global + app en la 2da región
4. Failover orquestado    → ARC                      ← recién ACÁ entra ARC
```

ARC es el paso 4. Sin los pasos 1–3, no tiene sentido.

## 5. DR **por tiers** (no todo necesita lo mismo)

El punto único de falla que más importa **no es cada cliente — es `ecolors-prod`** (la base `Admin`
+ el identity provider, DT-04): si esa región cae, **nadie se puede loguear en ningún licenciatario**.

| Tier | Qué | DR recomendado |
|---|---|---|
| **Plataforma** (`ecolors-prod`: Admin + auth) | Del que dependen todos | El candidato #1 a cross-region + ARC (RTO bajo) |
| **Licenciatarios** (sayer, ulbrika, …) | Datos propios de cada uno | Multi-AZ + backups (RTO más tolerante) |
| **NonProd** | Dev/QA | Backups y nada más |

Aplicar cross-region + ARC a *todo* duplicaría el costo sin necesidad. Concentrarlo en la plataforma
compartida da el mayor valor por el menor gasto.

## 6. Caveats específicos de ARC en esta arquitectura

- **App Runner complica el failover DNS.** App Runner usa su propia asociación de dominio por región
  (CNAME al endpoint). Para que ARC controle el failover, habría que montar registros Route 53 con
  routing de failover apuntando a dos servicios App Runner (uno por región), gateados por routing
  controls de ARC. No es imposible, pero no es tan directo como con un ALB + alias + health check.
- **Los frontends ya son resilientes.** CloudFront es global; si una región cae, el CDN sigue. El
  origen S3 se puede hacer cross-region (CRR + origin failover) con poco costo. El DR duro es de las
  **APIs y los datos**, no de los FE.
- **Los clusters de ARC tienen un costo fijo mensual considerable** (verificar en la pricing page).
  No es un servicio barato de dejar prendido.
- **Cross-region data:** RDS read replica cross-region o Aurora Global Database. Aurora Global da el
  menor RPO/RTO pero con mayor costo base — se cruza con la decisión RDS-vs-Aurora (ADR 0002).

## 7. Lo que falta decidir antes de implementar

1. **RTO/RPO objetivo** — sin esto, todo lo demás es adivinar. "Failover en minutos, cero pérdida"
   es carísimo; "restaurar de backup en horas" es barato.
2. **Alcance** — ¿resiliencia de AZ (barato) o failover de región (2x)? ¿Para todo, o solo para el
   platform compartido de ecolors?
3. **Región de standby** — us-east-2 es la candidata natural (vecina de us-east-1). Confirmar
   que App Runner esté disponible ahí.

## 8. Recomendación

Cuando se retome, **en este orden**:

1. **Multi-AZ en prod** (`db_multi_az = true`) — un toggle, ~+$12/mes, cubre la falla más común.
2. **Backups cross-region** de las bases de prod a us-east-2 — recovery point en otra región sin
   correr un standby completo. Cambio acotado al módulo `database`.
3. **Cross-region + ARC solo para `ecolors-prod`** (Admin + auth) — recién si el RTO lo justifica.

ARC no es el primer paso; es el último, y probablemente solo para la plataforma compartida.
