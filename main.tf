terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
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
  project            = var.google_cloud.project_id
  service            = each.key
  disable_on_destroy = false
  depends_on         = [google_project_service.cloud_resource_manager]
}

# Enable created endpoints API service
resource "google_project_service" "api-project-service" {
  service            = google_endpoints_service.api.service_name
  project            = var.google_cloud.project_id
  depends_on         = [google_endpoints_service.api]
  disable_on_destroy = true
}

########################################################################################################################
# Cloud Run backend for API
########################################################################################################################

resource "google_service_account" "api-backend_service_account" {
  account_id   = "${var.name}-api-backend"
  display_name = "Cloud Run backend Service Account"
  description  = "The Google Service Account used by the cloud run backend"
  depends_on   = [google_project_service.services["iam.googleapis.com"]]
}

module "env_secret" {
  for_each              = toset(nonsensitive(keys(var.env_vars))) # Make keys of variable nonsensitive.
  source                = "./modules/secret"
  secret_id             = each.key
  secret_data           = var.env_vars[each.key]
  service_account_email = google_service_account.api-backend_service_account.email
}

resource "google_cloud_run_service" "api-backend" {
  name     = "${var.name}-api-backend"
  location = var.google_cloud.region

  template {
    spec {
      containers {
        image = var.backend_image
        dynamic "env" {
          for_each = toset(nonsensitive(keys(var.env_vars)))
          content {
            name  = env.key
            value = "sm://${var.google_cloud.project_id}/${env.key}"
          }
        }
      }
      service_account_name = google_service_account.api-backend_service_account.email
    }
    metadata {
      annotations = var.cloud_run_annotations
    }
  }
  traffic {
    percent         = 100
    latest_revision = true
  }
}

########################################################################################################################
# Endpoints service
########################################################################################################################


# Create/update endpoints configuration based on OpenAPI
resource "google_endpoints_service" "api" {
  project      = var.google_cloud.project_id
  service_name = var.domain_name
  openapi_config = templatefile("./openapi.yaml.tpl", {
    host            = var.domain_name
    backend_address = google_cloud_run_service.api-backend.status[0].url
  })
}


########################################################################################################################
# Cloud Run Gateway for API
########################################################################################################################

# Create service account used by Cloud Run
resource "google_service_account" "api-gateway_service_account" {
  account_id   = "${var.name}-api-gateway"
  display_name = "Cloud Run gateway Service Account"
  description  = "The Google Service Account used by the cloud run gateway"
  depends_on   = [google_project_service.services["iam.googleapis.com"]]
}

# Give permission to Cloud Run gateway service-account to access private Cloud Run backend
resource "google_project_iam_member" "api-gateway_service_account_cloudrun_iam" {
  project = var.google_cloud.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.api-gateway_service_account.email}"
}

# Give permission to Cloud Run gateway service-account to control service management
resource "google_project_iam_member" "api-gateway_service_account_servicecontroller_iam" {
  project = var.google_cloud.project_id
  role    = "roles/servicemanagement.serviceController"
  member  = "serviceAccount:${google_service_account.api-gateway_service_account.email}"
}

# Create/update Cloud Run service
resource "google_cloud_run_service" "api-gateway" {
  name     = "${var.name}-api-gateway"
  location = var.google_cloud.region
  project  = var.google_cloud.project_id
  template {
    spec {
      containers {
        image = var.gateway_image
        env {
          name  = "ENDPOINTS_SERVICE_NAME"
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
  name     = var.domain_name

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
  location    = google_cloud_run_service.api-gateway.location
  project     = google_cloud_run_service.api-gateway.project
  service     = google_cloud_run_service.api-gateway.name
  policy_data = data.google_iam_policy.noauth.policy_data
}
