variable "repositories" {
  description = "Map of key (app slug) -> ECR repository name, e.g. { webapi = \"sayer-webapi-dev\" }."
  type        = map(string)
}

variable "image_tag_mutability" {
  description = "IMMUTABLE (recommended — a version tag can never be overwritten) or MUTABLE."
  type        = string
  default     = "IMMUTABLE"
}

variable "force_delete" {
  description = "Allow destroying a repository that still contains images."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
