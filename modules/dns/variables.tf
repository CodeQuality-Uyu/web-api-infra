variable "name" {
  description = "Prefix for tags."
  type        = string
}

variable "zone_name" {
  description = "Hosted zone / subdomain to create or reuse, e.g. sayer.ecolors.app."
  type        = string
}

variable "create_zone" {
  description = "Create the hosted zone. Set false to reuse an existing one via zone_id."
  type        = bool
  default     = true
}

variable "zone_id" {
  description = "Existing hosted zone id (used when create_zone = false)."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
