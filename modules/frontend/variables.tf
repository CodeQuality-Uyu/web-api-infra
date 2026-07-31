variable "name" {
  description = "Prefix, usually \"{client}-{env}\"."
  type        = string
}

variable "bucket_name" {
  description = "Globally-unique S3 bucket for the built SPA."
  type        = string
}

variable "domain_fqdn" {
  description = "Domain to serve the SPA on — typically the ZONE APEX (e.g. sayer.ecolors.app). Works at an apex because Route 53 uses an ALIAS record, not a CNAME."
  type        = string
}

variable "subject_alternative_names" {
  description = "Extra domains on the same distribution/cert. Each SERVES the same content (no redirect) — for a canonical www use `www_redirect` instead."
  type        = list(string)
  default     = []
}

variable "www_redirect" {
  description = "Also answer on www.<domain_fqdn> and 301-redirect it to the apex (canonical single URL, good for SEO/cookies). Adds the SAN, alias, DNS records and a CloudFront Function."
  type        = bool
  default     = false
}

variable "zone_id" {
  description = "Route 53 hosted zone id (from the client's foundation)."
  type        = string
}

variable "price_class" {
  description = "CloudFront price class, e.g. PriceClass_100 (NA+EU, cheapest) / PriceClass_All."
  type        = string
  default     = "PriceClass_100"
}

variable "release_version" {
  description = "Version currently served. The CI uploads each release under a \"<version>/\" prefix in the bucket; CloudFront's origin_path points here. Rollback = set this to a previously-uploaded version and apply (no rebuild). Empty string serves from the bucket root (legacy/unversioned)."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
