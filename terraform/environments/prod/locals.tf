locals {
  name_prefix = "doro-erp-prod"

  common_tags = {
    Project     = "Doro-ERP"
    Environment = "prod"
    Cell        = "alpha"
    Team        = "team2"
    ManagedBy   = "terraform"
  }

  network = data.terraform_remote_state.network.outputs

  workload_boundary_arn = "arn:aws:iam::${var.aws_account_id}:policy/doro-erp-guardrail-prod"

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
    edge-to-queue            = ["edge", "queue"]
    commerce-to-store-access = ["commerce", "store-access"]
    commerce-to-payment      = ["commerce", "payment"]
    store-access-to-commerce = ["store-access", "commerce"]
    store-access-to-payment  = ["store-access", "payment"]
    payment-to-commerce      = ["payment", "commerce"]
    payment-to-store-access  = ["payment", "store-access"]
    commerce-to-queue        = ["commerce", "queue"]
    queue-to-store-access    = ["queue", "store-access"]
    actor-context            = ["edge", "store-access", "commerce"]
  }

  provider_admin_namespace       = "doro-provider-admin"
  provider_admin_service_account = "provider-admin-edge-api"

  queue_names = toset([
    "commerce-events",
    "queue-events",
    "audit-events"
  ])
}
