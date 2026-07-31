variable "management_account_id" {
  description = "The management (root) account id — where consolidated billing lives and where the billing role is assigned."
  type        = string
}

# --- Account vending (OU + AWS account per NEW client) ---
# Only list clients to CREATE here. Existing accounts (sayer, ulbrika, ecolors-*) were made by
# hand and are intentionally NOT managed by this stack. Each entry vends: ou-<client>, and per
# environment ou-<client>-<env> + a new account acc-<client>-<env>.
#
# Each account needs its OWN globally-unique root email — one that no AWS account has ever used.
# (Plus-addressing is NOT assumed; provide a distinct real address per account.)
# Environment-first (docs/adr/0008): accounts are named <client>-<env> and placed under
# Workloads/<env>. Tenant is a tag, not an OU. No tenant OU fields — just the client + envs.
variable "clients_to_vend" {
  description = "Clients whose accounts Terraform creates. One account per environment, under Workloads/<env>."
  type = list(object({
    client = string # slug (lowercase); account name = <client>-<env>, Tenant tag
    environments = list(object({
      env   = string # must be a key of workload_environments (prod | nonprod)
      email = string # unique root email, never used by any AWS account before
    }))
  }))
  default = []

  validation {
    condition = length(distinct(flatten([for c in var.clients_to_vend : [for e in c.environments : lower(e.email)]]))) == length(flatten([for c in var.clients_to_vend : c.environments]))
    error_message = "Each vended account needs a unique root email."
  }
}

# Platform accounts: dedicated shared/governance accounts under a foundational OU (Security /
# Infrastructure), NOT workloads. E.g. a shared-services account for DNS, a finops account for
# cost tooling, a log-archive account. The management account stays minimal (org only).
variable "platform_accounts" {
  description = "Non-tenant accounts placed under a foundational OU (Security | Infrastructure)."
  type = list(object({
    name  = string # account name, e.g. "infrastructure", "finops", "log-archive"
    ou    = string # "Security" | "Infrastructure"
    email = string # unique root email
  }))
  default = []
}

variable "workload_environments" {
  description = "Environment slug -> OU display name. One OU is created per entry under Workloads; vended accounts are placed by matching env."
  type        = map(string)
  default = {
    prod    = "Prod"
    nonprod = "NonProd"
  }
}

# --- SCPs (Service Control Policies) ---
# All DENY-based (they compose with the default FullAWSAccess — no allow-list lockout) and always
# attached; the plan/apply is the review gate. Never apply to the management account (root
# break-glass preserved). Requires the SERVICE_CONTROL_POLICY type enabled (handled below).
variable "allowed_regions" {
  description = "Regions workload accounts may operate in (global services are exempt via region-lock)."
  type        = list(string)
  default     = ["us-east-1", "us-east-2"]
}

# DNS (ecolors.app + delegation role) moved to the dedicated infrastructure account —
# see stacks/infrastructure. The management account holds org governance only.

# --- Access (IAM Identity Center) ---
variable "access" {
  description = <<-EOT
    Permission sets to provision in Identity Center and assign to groups on the management account.
    Keyed by permission-set name. `groups` are Identity Center group DISPLAY NAMES (must already
    exist). `managed_policies` are AWS-managed policy ARNs; `session_hours` bounds the session.
  EOT
  type = map(object({
    description     = optional(string, "")
    session_hours   = optional(number, 4)
    managed_policies = list(string)
    groups          = list(string)
  }))
  default = {
    # Read-only billing: solves "I can't get into a role to just see billing".
    # NOTE: also flip the account setting "IAM user and role access to Billing information" ON
    # in the management account (console) — otherwise the console denies access despite this.
    "BillingReadOnly" = {
      description      = "Read-only access to consolidated billing and Cost Explorer."
      managed_policies = ["arn:aws:iam::aws:policy/AWSBillingReadOnlyAccess"]
      groups           = ["grp-ecolors-billing"] # CHANGE to your real Identity Center group
    }
  }
}
