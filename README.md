# GCP Endpoints API Terraform module

Terraform module which creates an API using Cloud Endpoints and Cloud Run on GCP.

## Usage
```hcl
module "api" {
  source        = "The-Academic-Observatory/api/google"
  
  name          = "observatory"
  domain_name   = "my-project-id.observatory.api.my.domain"
  backend_image = "us-docker.pkg.dev/my-project-id/observatory-platform/observatory-api:0.3.1"
  gateway_image = "gcr.io/endpoints-release/endpoints-runtime-serverless:2"
  google_cloud  = {
    project_id  = "my-project-id"
    region      = "us-central1"
  }
  env_vars = {
    "MY_ENV" = "my_secret_env"
  }
  cloud_run_annotations = {
    "autoscaling.knative.dev/maxScale" = "10"
  }
}
```

## Requirements
* A valid GCP project
* A registered custom domain name
* A service account with required permissions, that includes the following roles:
  * Cloud Run Admin (Create Cloud Run instances)
  * Project IAM Admin (Assign permissions to service accounts)
  * Secret Manager Admin (Manage the Google Cloud secrets created by env_vars)
  * Service Account Admin (Create Cloud Run service accounts)
  * Service Account User (Create Cloud Run instances with custom service account)
  * Service Management Administrator (Create Cloud Endpoints service)
  * Service Usage Admin (Enable Google API services)
* A built Docker image that is stored on the Google Artifact Registry  
* An OpenAPI configuration template, used by the endpoints service.

### OpenAPI configuration template
The Cloud Endpoints service is based on an OpenAPI specification, the service uses this specification to connect the 
registered custom domain to the created Cloud Run backend service.   
This means that for the 'host' setting inside the OpenAPI specification, the custom domain that is set for the 
'custom_domain' Terraform variable should be used. And for the 'address' setting inside the OpenAPI specification, the 
address of the created backend Cloud Run instance should be used.  
In order to do this, the Terraform configuration is set up so that it uses a template of the OpenAPI specification, 
with the 'host' and 'backend_address' as variables. See an example of the OpenAPI specification template below:

```yaml
swagger: '2.0'
info:
  title: API title
  description: API description
  version: 1.0.0
  contact:
    email: agent@observatory.academy
  license:
    name: Apache 2.0
    url: http://www.apache.org/licenses/LICENSE-2.0.html

schemes:
  - https
produces:
  - application/json
securityDefinitions:
  api_key:
    type: "apiKey"
    name: "key"
    in: "query"
security:
  - api_key: []

############# The two variables 'host' and 'backend_address' are used here
host: ${host}
x-google-backend:
  address: ${backend_address}
  protocol: h2
#############

tags:
- name: Tag
  description: Tag description

paths:
  /example:
    get:
      tags:
      - Example
      summary: Example endpoint
      operationId: coki_api_base.fixtures.api.example
      description: Description
      produces:
      - application/json
      responses:
        200:
          description: Success
```

One way to generate this template is by using the `generate-openapi-spec` command from the [coki-api-base](https://github.com/The-Academic-Observatory/coki-api-base) library.  
For example:
```
$ coki-api-base generate-openapi-spec openapi.yaml.jinja2 openapi.yaml.tpl --usage-type cloud_endpoints
```

The template file should be placed inside the same directory with the 'main.tf' configuration that uses this API module.

### Additional requirements for a 'Observatory API'
* The full URI of the SQL database

This should be in the format of:  
```
"postgresql://my-user-name:my-encoded-password@my-private-ip:5432/my-database-name"
```

If this is created by the Terraform configuration in 
[The-Academic-Observatory/observatory-platform](https://github.com/The-Academic-Observatory/observatory-platform/tree/develop/observatory-platform/observatory/platform/terraform),
then this could be shared from the corresponding Terraform workspace by adding this to the outputs of the main 
configuration:
```hcl
output "observatory_db_uri" {
  value = "postgresql://${google_sql_user.observatory_user.name}:${urlencode(var.observatory.postgres_password)}@${google_sql_database_instance.observatory_db_instance.private_ip_address}:5432/${google_sql_database.observatory_db.name}"
  description = "The observatory database URI"
  sensitive = true
}
```

It is possible to directly use this output inside this Terraform module, by granting the Terraform API workspace 
access to the main Terraform workspace where the database is created. This can be done from the general workspace 
settings of the main Terraform workspace, under 'Remote state sharing'.  
To then access the output from the remote state, add the following to the Terraform API configuration:
```hcl
# Get info from the observatory workspace if this is given
data "terraform_remote_state" "observatory" {
  backend = "remote"
  config  = {
    organization = "my-organization"
    workspaces   = {
      name = "my-main-tf-workspace"
    }
  }
}

locals {
    # Set the environment variables for the Cloud Run backend
  env_vars = {
    "OBSERVATORY_DB_URI" = data.terraform_remote_state.observatory[0].outputs.observatory_db_uri
  }
}
```

### Additional requirements for a 'Data API':
* The address of the Elasticsearch server
* An API key for the Elasticsearch server

The address of the Elasticsearch server can be obtained from the Elastic portal.

To generate an API key, execute in the Kibana Dev console:
```yaml
POST /_security/api_key
{
  "name": "my-dev-api-key",
  "role_descriptors": { 
    "role-read-access-all": {
      "cluster": ["all"],
      "index": [
        {
          "names": ["*"],
          "privileges": ["read", "view_index_metadata", "monitor"]
        }
      ]
    }
  }
}
```  

This returns:
```yaml
{
  "id" : "random_id",
  "name" : "my-dev-api-key",
  "api_key" : "random_api_key"
  "encoded": "random_id:random_api_key base64 encoded"
}
```

The value of the returned "encoded" field is used for the Terraform variable 'elasticsearch_api_key'.

## Environment Variable
If you use Terraform Cloud as the backend, the 'GOOGLE_CREDENTIALS' environment variable is used for authentication 
with the Google Provider. 
To setup this variable, create a new JSON key for a service account with the required permissions and remove the 
newlines so that it can be read as a Terraform environment variable.
To do this, either run in the terminal:
```shell
cat /path/to/credentials.json | tr '\n' ' '
```

Or run the following Python snippet:

```python
with open("/path/to/credentials.json", "r") as f:
    credentials = f.read().replace("\n", "")
```

## Terraform Variables
### google_cloud
The Google Cloud project settings, the project_id is used for all resources, the region is used for the two Cloud Run 
services.

### name
General name of the API, used to create a unique identifier for the following resources:
- Cloud Run backend service
- Cloud Run backend Service Account
- Cloud Run gateway service
- Cloud Run gateway Service Account

The name has to start with a lowercase letter and can be at most 16 characters long, because of limitations for the 
account_id of the service accounts. 

### domain_name
Full domain name for the resulting API, for example `my-project-id.observatory.api.custom.domain`.
The domain name should already be registered before deploying the Terraform resources.

### backend_image
URL of the Docker image used for the Cloud Run backend service. 
The image should be built beforehand and stored e.g. in the Google Artifact Registry.

### gateway_image
URL of the image used for the Cloud Run gateway service.
This should point to the endpoints runtime serverless image.

### env_vars
Dictionary with environment variable keys and values that will be added to the Cloud Run backend.
A Google Cloud secret is created for each variable, the variable is then accessed from inside the Cloud Run service
using berglas.
If google_cloud and env_vars are set as follows:
```hcl
google_cloud  = {
  project_id  = "my-project-id"
  region      = "us-central1"
}
env_vars = {
  "MY_ENV" = "my_secret_env"
}
```
Then the env variable created for the Cloud Run service will be:
```hcl
MY_ENV="sm://my-project-id/MY_ENV"
```
The secret value for this variable is obtained using Berglas inside the Cloud Run service, by accessing the value of 
the Google Cloud secret.

To use Berglas with your API the last lines of the Dockerfile should look like this for example:
```Docker
# Install berglas
COPY --from=gcr.io/berglas/berglas:latest /bin/berglas /bin/berglas

# Run app
ENTRYPOINT ["/bin/berglas", "exec",  "--", "gunicorn", "-b", "0.0.0.0:8080", "academic_observatory_api.server.app:app"]
```

### cloud_run_annotations
Dictionary with keys and values that will be added as annotations for the Cloud Run backend service, see 
https://cloud.google.com/run/docs/reference/rest/v1/RevisionTemplate and https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/ for more information.
