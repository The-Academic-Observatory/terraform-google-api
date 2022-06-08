# Simple API

Example to deploy an API with minimal settings.
For this example you will need to update the defaults for the variables to valid values.

This requires:
- A valid GCP project
- A service account with required permissions
- A registered custom domain name
- The service account to be added as a verified domain owner, see the 
[Google Docs](https://cloud.google.com/run/docs/mapping-custom-domains#add-verified) for more information.
- A built Docker image that is stored on the Google Artifact Registry
