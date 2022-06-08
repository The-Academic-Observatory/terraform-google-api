# GCP Endpoints API Terraform module

Terraform module which creates an API using Cloud Endpoints and Cloud Run on GCP.

## Usage
```hcl
module "api" {
  source        = "The-Academic-Observatory/api/google"
  
  name          = "observatory"
  domain_name   = "api.my.domain"
  subdomain     = "project_id"
  backend_image = "us-docker.pkg.dev/my-project-id/observatory-platform/observatory-api:0.3.1"
  gateway_image = "gcr.io/endpoints-release/endpoints-runtime-serverless:2"
  environment   = "develop"
  google_cloud  = {
    project_id  = "my-project-id"
    credentials = "/path/to/credentials.json"
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
* A service account with required permissions
* A registered custom domain name
* The service account to be added as a verified domain owner, see the 
[Google Docs](https://cloud.google.com/run/docs/mapping-custom-domains#add-verified) for more information.
* A built Docker image that is stored on the Google Artifact Registry  

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
access to the main Terraform workspace where the database is created.  
This can be done from the general workspace settings of the main Terraform workspace, under 'Remote state sharing'.
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
}
```

Concat id:api_key and base64 encode (this final value is what you use for the Terraform variable):
```bash
printf 'random_id:random_api_key' | base64
```



## Variables
### google_cloud
The Google Cloud project settings, the region is used for the two Cloud Run services.

### name
General name of the API, used as part of the final full domain name, see the domain name examples below.

Also used to create a unique identifier for the following resources:
- Cloud Run backend service
- Cloud Run backend Service Account
- Cloud Run gateway service
- Cloud Run gateway Service Account

The name has to start with a lowercase letter and can be at most 16 characters long, because of limitations for the 
account_id of the service accounts. 

### domain_name
Base domain name for the resulting API, see the domain name examples below.

### subdomain
Describes how the subdomain should be determined, this is either set to 'project_id' or 'environment'.  
When set to 'project_id' the subdomain is derived from the GCP project id, when set to 'environment' the 
subdomain is derived from the environment variable. 
See also the domain name examples below.

### environment
The environment setting, has to be one of 'develop', 'staging', or 'production'. 
Used for the final full domain name if the subdomain variable is set to 'environment', see the domain name examples 
below.

### backend_image
URL of the image used for the Cloud Run backend service. 
The image should be built beforehand and stored in the Google Artifact Registry.

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
  credentials = "/path/to/credentials.json"
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

## Domain name examples
Below are some examples with the resulting full domain name based on different variable settings.

```hcl
# Variables
name         = "observatory"
domain_name  = "api.my.domain"
subdomain    = "project_id"
environment  = "develop"
google_cloud = {
  project_id = "my-project-id"
}

# Full domain name: "my-project-id.observatory.api.my.domain"
```

```hcl
# Variables
name         = "observatory"
domain_name  = "api.my.domain"
subdomain    = "environment"
environment  = "develop"
google_cloud = {
  project_id = "my-project-id"
}

# Full domain name: "develop.observatory.api.my.domain"
```

```hcl
# Variables
name         = "observatory"
domain_name  = "api.my.domain"
subdomain    = "environment"
environment  = "staging"
google_cloud = {
  project_id = "my-project-id"
}

# Full domain name: "staging.observatory.api.my.domain"
```

```hcl
# Variables
name         = "observatory"
domain_name  = "api.my.domain"
subdomain    = "environment"
environment  = "production"
google_cloud = {
  project_id = "my-project-id"
}

# Full domain name: "observatory.api.my.domain"
```