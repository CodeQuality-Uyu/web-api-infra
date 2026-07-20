# The ONE cross-stack read: this client's foundation outputs.
data "terraform_remote_state" "foundation" {
  backend = "remote"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = var.foundation_workspace
    }
  }
}

locals {
  f = data.terraform_remote_state.foundation.outputs
}
