variable "name" {
  type = string
}

variable "bucket_name" {
  description = "Globally-unique bucket name."
  type        = string
}

variable "domain_fqdn" {
  description = "Custom domain for the CloudFront distribution, e.g. assets.sayer.ecolors.app."
  type        = string
}

variable "zone_id" {
  type = string
}

variable "allowed_origins" {
  description = "CORS allowed origins (exact, incl. scheme)."
  type        = list(string)
  default     = []
}

variable "temporary_folder" {
  description = "Prefix whose objects expire after 1 day."
  type        = string
  default     = "temporary"
}

variable "tags" {
  type    = map(string)
  default = {}
}
