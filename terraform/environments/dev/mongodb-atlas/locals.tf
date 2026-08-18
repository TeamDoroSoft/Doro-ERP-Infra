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
    vpc_id           = "vpc-0fd66ab523924fc38"
    vpc_cidr         = "10.24.0.0/16"
    data_a_subnet_id = "subnet-0ab877d61c6444293"
    data_c_subnet_id = "subnet-0ae8607f5fe2f5f7b"
  }
}
