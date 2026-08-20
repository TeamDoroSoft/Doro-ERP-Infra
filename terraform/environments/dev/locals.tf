locals {
  name_prefix = "doro-erp-dev"

  common_tags = {
    Project     = "Doro-ERP"
    Environment = "dev"
    Cell        = "alpha"
    Team        = "team2"
    ManagedBy   = "terraform"
  }

  existing_network = {
    vpc_id                = "vpc-0fd66ab523924fc38"
    vpc_cidr              = "10.24.0.0/16"
    public_a_subnet_id    = "subnet-05d2f0c9b6c2cd5ec"
    public_c_subnet_id    = "subnet-034c5c3b44fc22b46"
    app_a_subnet_id       = "subnet-000e8271451fdf084"
    app_c_subnet_id       = "subnet-063e9f24a951f3405"
    data_a_subnet_id      = "subnet-0ab877d61c6444293"
    data_c_subnet_id      = "subnet-0ae8607f5fe2f5f7b"
    private_app_route_id  = "rtb-087a7c346ff32a3ee"
    private_data_route_id = "rtb-0fe96fa5d2b5c16a3"
    vpc_endpoint_sg_name  = "team2-doro-sg-vpce"
  }

  workload_boundary_arn = "arn:aws:iam::${var.aws_account_id}:policy/doro-erp-guardrail-dev"

  app_names = toset([
    "edge",
    "store-access",
    "commerce",
    "payment",
    "queue",
    "audit"
  ])

  migration_app_names = toset([
    "store-access",
    "commerce",
    "payment",
    "queue"
  ])

  hmac_directions = {
    edge-to-store-access     = ["edge", "store-access"]
    edge-to-audit            = ["edge", "audit"]
    edge-to-payment          = ["edge", "payment"]
    edge-to-commerce         = ["edge", "commerce"]
    commerce-to-store-access = ["commerce", "store-access"]
    store-access-to-commerce = ["store-access", "commerce"]
    payment-to-commerce      = ["payment", "commerce"]
    commerce-to-queue        = ["commerce", "queue"]
    actor-context            = ["edge", "store-access", "commerce"]
  }

  queue_names = toset([
    "commerce-events",
    "queue-events",
    "audit-events"
  ])
}
