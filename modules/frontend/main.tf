# Static SPA hosting at the ZONE APEX (e.g. sayer.ecolors.app).
# The apex works because Route 53 points at CloudFront with an ALIAS record — a CNAME is not
# allowed at an apex, which is why the APIs live on a subdomain via App Runner (see contracts).
data "aws_caller_identity" "current" {}

locals {
  # www is an extra name on the SAME cert/distribution; the CloudFront Function below turns it
  # into a 301 to the apex, so the apex stays the single canonical URL.
  extra_domains = distinct(compact(concat(
    var.subject_alternative_names,
    var.www_redirect ? ["www.${var.domain_fqdn}"] : [],
  )))

  all_domains = concat([var.domain_fqdn], local.extra_domains)
}

# --- Bucket (private; only this CloudFront reads it, via OAC) ---
resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  tags   = merge(var.tags, { Name = var.bucket_name })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- ACM cert in us-east-1 (CloudFront requires it there), DNS-validated in the client zone ---
resource "aws_acm_certificate" "cf" {
  provider                  = aws.us_east_1
  domain_name               = var.domain_fqdn
  subject_alternative_names = local.extra_domains
  validation_method         = "DNS"
  lifecycle { create_before_destroy = true }
  tags = merge(var.tags, { Name = "${var.name}-fe-acm" })
}

resource "aws_route53_record" "cf_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cf.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }
  zone_id         = var.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cf" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cf.arn
  validation_record_fqdns = [for r in aws_route53_record.cf_validation : r.fqdn]
}

# --- CloudFront (SPA) ---
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.name}-fe-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Modern managed cache policy (replaces the legacy forwarded_values block).
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

# Canonical-host redirect: www.<apex> -> <apex> with a 301, preserving path and query string.
# Runs at the edge on every viewer request; non-www hosts pass straight through.
resource "aws_cloudfront_function" "www_redirect" {
  count   = var.www_redirect ? 1 : 0
  name    = "${var.name}-fe-www-redirect"
  runtime = "cloudfront-js-2.0"
  comment = "301 www.${var.domain_fqdn} -> ${var.domain_fqdn}"
  publish = true

  code = <<-EOT
    function handler(event) {
      var req = event.request;
      var host = (req.headers.host && req.headers.host.value) || '';
      if (host.indexOf('www.') !== 0) {
        return req;
      }

      var qs = '';
      var keys = Object.keys(req.querystring || {});
      if (keys.length > 0) {
        var parts = [];
        for (var i = 0; i < keys.length; i++) {
          var k = keys[i];
          var v = req.querystring[k];
          if (v.multiValue) {
            for (var j = 0; j < v.multiValue.length; j++) {
              parts.push(k + '=' + v.multiValue[j].value);
            }
          } else {
            parts.push(v.value === '' ? k : k + '=' + v.value);
          }
        }
        qs = '?' + parts.join('&');
      }

      return {
        statusCode: 301,
        statusDescription: 'Moved Permanently',
        headers: { location: { value: 'https://${var.domain_fqdn}' + req.uri + qs } }
      };
    }
  EOT
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = local.all_domains
  price_class         = var.price_class

  # Serve from the "<version>/" prefix the CI uploaded to. Repointing this (via release_version)
  # is the rollback: no rebuild, the previous version's objects are still in the bucket.
  # CloudFront prepends origin_path to every origin request, including the error-page fetch, so
  # default_root_object and the custom_error_response paths below resolve under the version too.
  origin {
    domain_name              = aws_s3_bucket.this.bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
    origin_path              = var.release_version != "" ? "/${var.release_version}" : null
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id

    dynamic "function_association" {
      for_each = var.www_redirect ? [1] : []
      content {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.www_redirect[0].arn
      }
    }
  }

  # Client-side routing: any unknown path must return the SPA shell, not an error.
  # With OAC and no s3:ListBucket, a missing key returns 403 — so both are mapped.
  custom_error_response {
    error_caching_min_ttl = 0
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
  }

  custom_error_response {
    error_caching_min_ttl = 0
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cf.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  tags = merge(var.tags, { Name = "${var.name}-fe-cdn" })
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid       = "AllowCloudFrontRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json
}

# --- Apex DNS: ALIAS records (A + AAAA). This is what makes the zone apex work. ---
resource "aws_route53_record" "a" {
  for_each = toset(local.all_domains)

  zone_id = var.zone_id
  name    = each.value
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "aaaa" {
  for_each = toset(local.all_domains)

  zone_id = var.zone_id
  name    = each.value
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
