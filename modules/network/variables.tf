variable "name" {
  description = "Prefix for all resources (usually \"{client}-{env}\")."
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Number of AZs to spread subnets across."
  type        = number
  default     = 2
}

variable "enable_nat" {
  description = "Create a NAT gateway. Needed only if the app makes outbound internet calls."
  type        = bool
  default     = true
}

variable "enable_bastion" {
  description = "Create the SSM bastion for DB admin access."
  type        = bool
  default     = true
}

variable "bastion_instance_type" {
  description = "Bastion instance type."
  type        = string
  default     = "t4g.nano"
}

variable "tags" {
  type    = map(string)
  default = {}
}
