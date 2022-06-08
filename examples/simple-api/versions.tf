terraform {
  backend "remote" {
    workspaces {
      prefix = "observatory-"
    }
  }

  required_version = ">= 1.0.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 3.85.0"
    }
  }
}