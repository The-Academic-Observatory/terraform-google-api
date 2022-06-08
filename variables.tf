variable "google_cloud" {
  description = <<EOF
The Google Cloud settings for the Observatory Platform.

project_id: the Google Cloud project id.
credentials: the path to the Google Cloud credentials.
region: the Google Cloud region.
zone: the Google Cloud zone.
EOF
  type = object({
    project_id  = string
    credentials = string
    region      = string
  })
}

variable "name" {
  description = "Name of the API project, e.g. observatory, ao or oaebu"
  type        = string
  validation {
    condition     = length(var.name) <= 16
    error_message = "Name of the API has to be <= 16 characters."
  }
}

variable "domain_name" {
  description = "The custom domain name for the API, used for the google cloud endpoints service"
  type        = string
  sensitive   = true
}

variable "subdomain" {
  description = "Can be either 'project_id' or 'environment', used to determine a prefix for the domain_name"
  type        = string
  validation {
    condition     = var.subdomain == "project_id" || var.subdomain == "environment"
    error_message = "The subdomain must either be 'project_id' or 'environment'."
  }
}

variable "environment" {
  description = "The environment type: develop, staging or production."
  type        = string
  validation {
    condition     = var.environment == "develop" || var.environment == "staging" || var.environment == "production"
    error_message = "The environment must be one of 'develop', 'staging' or 'production'."
  }
}

variable "backend_image" {
  description = "The image URL that will be used for the Cloud Run backend, e.g. 'us-docker.pkg.dev/your-project-name/observatory-platform/observatory-api:0.3.1'"
  type        = string
  sensitive   = true
}
variable "gateway_image" {
  description = "The image URL that will be used for the Cloud Run gateway (endpoints service), e.g. 'gcr.io/endpoints-release/endpoints-runtime-serverless:2'"
  type        = string
}

variable "env_vars" {
  description = <<EOF
Dictionary with environment variable keys and values that will be added to the Cloud Run backend.
A Google Cloud secret is created for each variable, the variable is then accessed from inside the Cloud Run service
using berglas.
EOF
  type        = map(string)
  sensitive   = true
}

variable "cloud_run_annotations" {
  description = <<EOF
The annotations that are added to the Cloud Run backend service.
EOF
  type        = map(string)
  sensitive   = true
}