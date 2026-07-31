variable "name" {
  description = "Prefix, usually \"{client}-{app}-{env}\"."
  type        = string
}

variable "image_uri" {
  description = "Full ECR image URI incl. tag."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the App Runner VPC connector."
  type        = list(string)
}

variable "connector_sg_ids" {
  description = "Security groups for the VPC connector (typically the shared db_clients SG, which RDS already allows)."
  type        = list(string)
}

variable "cpu" {
  description = "App Runner vCPU units, e.g. \"1024\" = 1 vCPU."
  type        = string
  default     = "1024"
}

variable "memory" {
  description = "App Runner memory in MB, e.g. \"2048\" = 2 GB."
  type        = string
  default     = "2048"
}

variable "port" {
  description = "Container port the API listens on."
  type        = string
  default     = "8080"
}

variable "health_path" {
  type    = string
  default = "/health"
}

variable "auto_deploy" {
  description = "Let App Runner redeploy on any push to the tag. Default false: Terraform pins the version, so promotion is a deliberate image_version bump + apply (a clean one-line plan) rather than an out-of-band push."
  type        = bool
  default     = false
}

variable "domain_fqdn" {
  description = "Custom subdomain to bind, e.g. api.sayer.ecolors.app. Must NOT be the zone apex."
  type        = string
}

variable "zone_id" {
  description = "Route53 hosted zone id to write the app + validation records into."
  type        = string
}

variable "runtime_env" {
  description = "Plaintext env vars for the container."
  type        = map(string)
  default     = {}
}

variable "runtime_secrets" {
  description = "Map of ENV_VAR_NAME -> SSM/Secrets ARN, injected at runtime."
  type        = map(string)
  default     = {}
}

variable "secret_source_arns" {
  description = "ARNs the instance role may read (SSM params / secrets)."
  type        = list(string)
  default     = []
}

variable "kms_key_arns" {
  description = "KMS key ARNs to allow Decrypt on (for SecureString secrets)."
  type        = list(string)
  default     = []
}

variable "blobs_bucket_arn" {
  description = "ARN of the blobs bucket this app reads/writes at runtime. Null = the app has no blob storage; grants no S3 access."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
