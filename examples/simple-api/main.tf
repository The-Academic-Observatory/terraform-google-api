########################################################################################################################
# Configure Google Cloud Provider
########################################################################################################################

provider "google" {
  credentials = var.google_cloud.credentials
  project     = var.google_cloud.project_id
  region      = var.google_cloud.region
}

module "api" {
  source                = "../../"
  google_cloud          = var.google_cloud
  name                  = var.name
  domain_name           = var.domain_name
  subdomain             = var.subdomain
  environment           = var.environment
  backend_image         = var.backend_image
  gateway_image         = var.gateway_image
  env_vars              = {}
  cloud_run_annotations = {}
}

