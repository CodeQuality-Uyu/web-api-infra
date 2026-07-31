locals {
  # Includes the frontend slug: a client-env can host several SPAs in the same AWS account,
  # and names like the OAC or the CloudFront function must not collide between them.
  name = "${var.client}-${var.frontend_name}-${var.environment}"

  tags = merge(var.tags, {
    Client         = var.client
    Environment    = var.environment
    Frontend       = var.frontend_name
    ConsumesApps   = join(",", var.consumes_apps)
    ReleaseVersion = var.release_version
  })

  # Default to the zone apex — the domain you type in the browser (e.g. sayer.ecolors.app).
  # Only one frontend per client-env may take the apex; the rest set `domain` explicitly.
  domain = coalesce(var.domain, local.f.zone_name)
}

# Records when release_version last changed (same pattern as the API's APP_VERSION_DATE):
# steady on unrelated applies, re-stamped only on a version bump.
resource "time_static" "release" {
  triggers = {
    version = var.release_version
  }
}

module "frontend" {
  source = "../../modules/frontend"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name                      = local.name
  bucket_name               = var.bucket_name
  domain_fqdn               = local.domain
  subject_alternative_names = var.subject_alternative_names
  www_redirect              = var.www_redirect
  zone_id                   = local.f.zone_id
  price_class               = var.price_class
  release_version           = var.release_version

  tags = merge(local.tags, { ReleaseDate = time_static.release.rfc3339 })
}
