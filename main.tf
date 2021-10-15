terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "~> 3.85.0"
    }
  }
}


########################################################################################################################
# Enable Google API services
########################################################################################################################

resource "google_project_service" "cloud_resource_manager" {
  project = var.google_cloud.project_id
  service = "cloudresourcemanager.googleapis.com"
}

resource "google_project_service" "services" {
  for_each = toset(["servicemanagement.googleapis.com", "servicecontrol.googleapis.com", "endpoints.googleapis.com",
    "iam.googleapis.com", "secretmanager.googleapis.com"])
  project = var.google_cloud.project_id
  service = each.key
  disable_on_destroy = false
  depends_on = [google_project_service.cloud_resource_manager]
}

# Enable created endpoints API service
resource "google_project_service" "api-project-service" {
  service = google_endpoints_service.api.service_name
  project = var.google_cloud.project_id
  depends_on = [google_endpoints_service.api]
  disable_on_destroy = true
}

########################################################################################################################
# Cloud Run backend for API
########################################################################################################################

resource "google_service_account" "api-backend_service_account" {
  account_id   = "${var.api.name}-api-backend"
  display_name = "Cloud Run backend Service Account"
  description = "The Google Service Account used by the cloud run backend"
  depends_on = [google_project_service.services["iam.googleapis.com"]]
}

module "elasticsearch_host" {
  count = var.data_api.elasticsearch_host != null ? 1 : 0
  source = "./modules/secret"
  secret_id = "${var.api.name}-elasticsearch_host"
  secret_data = var.data_api.elasticsearch_host
  service_account_email = google_service_account.api-backend_service_account.email
}

module "elasticsearch_api_key" {
  count = var.data_api.elasticsearch_api_key != null ? 1 : 0
  source = "./modules/secret"
  secret_id = "${var.api.name}-elasticsearch_api_key"
  secret_data = var.data_api.elasticsearch_api_key
  service_account_email = google_service_account.api-backend_service_account.email
}

module "observatory_db_uri" {
  count = var.observatory_api.observatory_db_uri != null ? 1 : 0
  source = "./modules/secret"
  secret_id = "observatory_db_uri"
  secret_data = var.observatory_api.observatory_db_uri
  service_account_email = google_service_account.api-backend_service_account.email
}

locals {
  common_annotations = {
    "autoscaling.knative.dev/maxScale" = "10"
    "build_info" = var.build_info
  }
  vpc_connector_name = var.observatory_api.vpc_connector_name != null ? var.observatory_api.vpc_connector_name : ""
  observatory_api_annotations = merge(
  {
        "run.googleapis.com/vpc-access-egress" : "private-ranges-only"
        "run.googleapis.com/vpc-access-connector" = "projects/${var.google_cloud.project_id}/locations/${var.google_cloud.region}/connectors/${local.vpc_connector_name}"
  },
          local.common_annotations)
  annotations = var.observatory_api.vpc_connector_name != null ? local.observatory_api_annotations : local.common_annotations

  env_vars = {
    "ES_HOST" = ["sm://${var.google_cloud.project_id}/${var.api.name}-elasticsearch_host", var.data_api.elasticsearch_host]
    "ES_API_KEY" = ["sm://${var.google_cloud.project_id}/${var.api.name}-elasticsearch_api_key", var.data_api.elasticsearch_api_key]
    "OBSERVATORY_DB_URI" = ["sm://${var.google_cloud.project_id}/observatory_db_uri", var.observatory_api.observatory_db_uri]
  }
}

resource "google_cloud_run_service" "api-backend" {
  name     = "${var.api.name}-api-backend"
  location = var.google_cloud.region

  template {
    spec {
      containers {
        image = "gcr.io/${var.google_cloud.project_id}/${var.api.name}-api:${var.api.image_tag}"
        dynamic "env" {
          for_each = {for key, values in local.env_vars : key => values[0] if values[1] != null}
          content {
            name = env.key
            value = env.value
          }
        }
      }
      service_account_name = google_service_account.api-backend_service_account.email
    }
    metadata {
      annotations = local.annotations
    }
  }
  traffic {
    percent = 100
    latest_revision = true
  }
}

########################################################################################################################
# Endpoints service
########################################################################################################################

locals {
  # Use the project id as a subdomain for a project that will not host the final production API. The endpoint service/domain name is
  # unique and can only be used in 1 project. Once it is created in one project, it can't be fully deleted for 30 days.
  project_domain_name = "${var.google_cloud.project_id}.${var.api.name}.${var.api.domain_name}"
  environment_domain_name = var.environment == "production" ? "${var.api.name}.${var.api.domain_name}" : "${var.environment}.${var.api.name}.${var.api.domain_name}"
  full_domain_name =  var.api.subdomain == "project_id" ? local.project_domain_name : local.environment_domain_name
}

# Create/update endpoints configuration based on OpenAPI
resource "google_endpoints_service" "api" {
  project = var.google_cloud.project_id
  service_name = local.full_domain_name
  openapi_config = templatefile("./openapi.yaml.tpl", {
    host = local.full_domain_name
    backend_address = google_cloud_run_service.api-backend.status[0].url
  })
}


########################################################################################################################
# Cloud Run Gateway for API
########################################################################################################################

# Create service account used by Cloud Run
resource "google_service_account" "api-gateway_service_account" {
  account_id = "${var.api.name}-api-gateway"
  display_name = "Cloud Run gateway Service Account"
  description = "The Google Service Account used by the cloud run gateway"
  depends_on = [google_project_service.services["iam.googleapis.com"]]
}

# Give permission to Cloud Run gateway service-account to access private Cloud Run backend
resource "google_project_iam_member" "api-gateway_service_account_cloudrun_iam" {
  project = var.google_cloud.project_id
  role = "roles/run.invoker"
  member = "serviceAccount:${google_service_account.api-gateway_service_account.email}"
}

# Give permission to Cloud Run gateway service-account to control service management
resource "google_project_iam_member" "api-gateway_service_account_servicecontroller_iam" {
  project = var.google_cloud.project_id
  role = "roles/servicemanagement.serviceController"
  member = "serviceAccount:${google_service_account.api-gateway_service_account.email}"
}

# Create/update Cloud Run service
resource "google_cloud_run_service" "api-gateway" {
  name = "${var.api.name}-api-gateway"
  location = var.google_cloud.region
  project = var.google_cloud.project_id
  template {
    spec {
      containers {
        image = "gcr.io/endpoints-release/endpoints-runtime-serverless:2"
        env {
          name = "ENDPOINTS_SERVICE_NAME"
          value = google_endpoints_service.api.service_name
        }
      }
      service_account_name = google_service_account.api-gateway_service_account.email
    }
  }
  depends_on = [google_endpoints_service.api, google_project_iam_member.api-gateway_service_account_servicecontroller_iam]
}

# Create custom domain mapping for cloud run gateway
resource "google_cloud_run_domain_mapping" "default" {
  location = google_cloud_run_service.api-gateway.location
  name = local.full_domain_name

  metadata {
    namespace = var.google_cloud.project_id
  }

  spec {
    route_name = google_cloud_run_service.api-gateway.name
  }
}

# Create public access policy
data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

# Enable public access policy on gateway (access is restricted with API key by openapi config)
resource "google_cloud_run_service_iam_policy" "noauth-endpoints" {
  location = google_cloud_run_service.api-gateway.location
  project = google_cloud_run_service.api-gateway.project
  service = google_cloud_run_service.api-gateway.name
  policy_data = data.google_iam_policy.noauth.policy_data
}
