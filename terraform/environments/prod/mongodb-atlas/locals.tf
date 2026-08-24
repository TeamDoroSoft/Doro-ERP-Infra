locals {
  name_prefix = "doro-erp-prod-alpha"

  common_tags = {
    Project     = "Doro-ERP"
    Environment = "prod"
    Cell        = "alpha"
    Team        = "team2"
    ManagedBy   = "terraform"
  }

  network = data.terraform_remote_state.network.outputs
}
