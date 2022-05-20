variable "environment" {
  description = "The environment type: develop, staging or production."
  type = string
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
    project_id = string
    credentials = string
    region = string
    zone = string
    data_location = string
  })
}

variable "api" {
  description = <<EOF
Settings related to the API

name: Name of the API project, e.g. academic-observatory or oaebu
//package_name: Local path to the Data API package, e.g. /path/to/academic_observatory_workflows_api
domain_name: the custom domain name for the API, used for the google cloud endpoints service
subdomain: can be either 'project_id' or 'environment', used to determine a prefix for the domain_name
backend_image: The image URL that will be used for the Cloud Run backend.
gateway_image: The image URL that will be used for the Cloud Run gateway (endpoints service)
EOF
  type = object({
    name            = string
    domain_name     = string
    subdomain       = string
    backend_image   = string
    gateway_image   = string
  })
}

variable "env_vars" {
  description = <<EOF
Dictionary with environment variable keys and values that will be added to the Cloud Run backend.
A Google Cloud secret is created for each variable, the variable is then accessed from inside the Cloud Run service
using berglas.
EOF
  type = map(string)
  sensitive = true
}

variable "cloud_run_annotations" {
  description = <<EOF
The annotations that are added to the Cloud Run backend service.
EOF
  type = map(string)
  sensitive = true
}