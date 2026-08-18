locals {
  name_prefix = "doro-erp-dev-alpha"

  common_tags = {
    Project     = "Doro-ERP"
    Environment = "dev"
    Cell        = "alpha"
    Team        = "team2"
    ManagedBy   = "terraform"
  }

  network = {
    vpc_id   = "vpc-0fd66ab523924fc38"
    vpc_cidr = "10.24.0.0/16"
  }
}
