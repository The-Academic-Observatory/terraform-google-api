variable "environment" {
  description = "The environment type: develop, staging or production."
  type        = string
}

variable "google_cloud" {
  description = <<EOF
The Google Cloud settings for the Observatory Platform.

project_id: the Google Cloud project id.
credentials: the path to the Google Cloud credentials.
region: the Google Cloud region.
zone: the Google Cloud zone.
data_location: the data location for storing buckets.
EOF
  type = object({
    project_id    = string
    credentials   = string
    region        = string
    zone          = string
    data_location = string
  })
}

variable "name" {
  description = "Name of the API project, e.g. observatory, ao or oaebu"
  type        = string
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
variable "backend_image" {
  description = "The image URL that will be used for the Cloud Run backend."
  type        = string
  sensitive   = true
}
variable "gateway_image" {
  description = "The image URL that will be used for the Cloud Run gateway (endpoints service)"
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