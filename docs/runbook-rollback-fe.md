# Runbook — Promover / hacer rollback de un frontend

Cada release del FE queda en el bucket bajo un prefijo **inmutable** `<version>/`. CloudFront sirve
la que le indica `origin_path`, que se maneja de forma **declarativa** con `version` en
`clients.auto.tfvars`. Por eso el rollback **no recompila nada**: solo repointa a una versión que ya
está en el bucket.

```
s3://ecolors-seller-nonprod-web/
  1.4.0/  index.html  assets/…      ← release anterior (queda intacto)
  1.5.0/  index.html  assets/…      ← release actual   ← origin_path = /1.5.0
```

## Modelo de dos pasos

| Paso | Quién | Qué hace |
|------|-------|----------|
| **Publicar** | GitHub Actions (`deploy-frontend.yml`) | build + subida a `s3://<bucket>/<version>/`. NO cambia lo que se sirve. |
| **Promover / rollback** | Terraform (este repo) | mover `origin_path` cambiando `version` en `clients.auto.tfvars`. |

Publicar una versión nueva **no** la pone en vivo hasta que Terraform mueve el puntero. Eso es lo que
permite el rollback: la versión anterior nunca se borró.

## Promover una versión nueva

Requisito: la versión ya fue publicada por el CI (existe `s3://<bucket>/<version>/`).

1. En [`factory/clients.auto.tfvars`](../factory/clients.auto.tfvars), en el frontend correspondiente:
   ```hcl
   { name = "seller", version = "1.5.0", ... }   # antes 1.4.0
   ```
2. Aplicar el workspace del frontend (`{client}-{name}-{env}-frontend`). Terraform mueve
   `origin_path` a `/1.5.0` y re-estampa `release_date`.
3. **Invalidar la caché** para que el corte sea inmediato (output `invalidate_command`):
   ```bash
   aws cloudfront create-invalidation --distribution-id <DIST_ID> --paths '/*'
   ```
   > Sin invalidar igual se corrige solo en segundos: `index.html` va con `no-cache` y los assets son
   > content-hashed. La invalidación solo lo hace instantáneo y determinístico.

## Rollback (volver a una versión anterior)

Idéntico, pero apuntando a una versión **ya publicada** previamente:

1. En `clients.auto.tfvars`, bajar `version` a la anterior:
   ```hcl
   { name = "seller", version = "1.4.0", ... }   # revertir 1.5.0 -> 1.4.0
   ```
2. Aplicar el workspace del frontend → `origin_path` vuelve a `/1.4.0`.
3. Invalidar la caché (mismo comando de arriba).

No hay build, no hay resubida: los objetos de `1.4.0/` siguen en el bucket. El rollback tarda lo que
tarda el apply + la invalidación (segundos).

## Notas operativas

- **Retención:** los prefijos viejos se acumulan. Agregá una lifecycle rule de S3 para expirar
  versiones más viejas que N días, o limpiá a mano dejando las últimas para poder revertir.
- **La versión tiene que existir en el bucket.** Si apuntás a una `version` que el CI nunca subió,
  CloudFront devuelve 403/404 (que el `custom_error_response` mapea al `index.html` de esa versión, que
  tampoco existe → error). Confirmá el prefijo antes de promover: `aws s3 ls s3://<bucket>/`.
- **Fecha:** no va en el prefijo (solo la versión). Queda registrada en el output `release_date`
  (estampado por `time_static`) y en el `LastModified` de los objetos en S3.
