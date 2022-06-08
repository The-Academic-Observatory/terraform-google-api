variable "google_cloud" {
  type = object({
    project_id  = string
    credentials = string
    region      = string
  })
  default = {
    project_id  = "my-project-id"
    credentials = "json-credentials"
    region      = "us-central1"
  }
}

variable "name" {
  type    = string
  default = "observatory"
}

variable "domain_name" {
  type    = string
  default = "my-project-id.observatory.api.my.domain"
}

variable "backend_image" {
  type    = string
  default = "us-docker.pkg.dev/my-project-id/observatory-platform/observatory-api:0.3.1"
}

variable "gateway_image" {
  type    = string
  default = "gcr.io/endpoints-release/endpoints-runtime-serverless:2"
}
