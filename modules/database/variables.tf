variable "name" {
  description = "Prefix, usually \"{client}-{app}-{env}\"."
  type        = string
}

variable "environment" {
  description = "dev | stage | prod."
  type        = string
}

variable "ssm_prefix" {
  description = "SSM Parameter Store path prefix for connection strings, e.g. /myorg."
  type        = string
  default     = "/app"
}

variable "subnet_ids" {
  description = "Private subnet IDs for the DB subnet group."
  type        = list(string)
}

variable "vpc_id" {
  type = string
}

variable "allowed_sg_ids" {
  description = "SG IDs allowed to reach Postgres (App Runner connector SG, bastion SG, ...)."
  type        = list(string)
  default     = []
}

variable "publicly_accessible" {
  description = "Expose the RDS on a public endpoint (still gated by the SG). Needed when apps in OTHER accounts/VPCs must reach a shared database. Keep false for single-account."
  type        = bool
  default     = false
}

variable "external_allowed_cidrs" {
  description = "CIDRs allowed to reach Postgres from outside the VPC (e.g. the NAT EIPs of consumer client-envs). Only meaningful with publicly_accessible = true."
  type        = list(string)
  default     = []
}

variable "db_names" {
  description = "Logical databases to expose as connection strings."
  type        = list(string)
  default     = []
}

variable "engine_version" {
  type    = string
  default = "16.8"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "max_allocated_storage" {
  type    = number
  default = 100
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "skip_final_snapshot" {
  type    = bool
  default = false
}

variable "master_username" {
  type    = string
  default = "master"
}

variable "iam_authentication" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
