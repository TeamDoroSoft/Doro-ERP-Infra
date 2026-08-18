terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.58"
    }

    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = "~> 2.14"
    }
  }

  backend "s3" {}
}
