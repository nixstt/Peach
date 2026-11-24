variable "project_id" {
  description = "Google Cloud project ID with billing enabled."
  type        = string
}

variable "region" {
  description = "Region used for Cloud Run, Cloud SQL, and Artifact Registry."
  type        = string
  default     = "us-central1"
}

variable "name_prefix" {
  description = "Prefix used for GCP resource names."
  type        = string
  default     = "spry"
}

variable "database_name" {
  description = "PostgreSQL database created for the application."
  type        = string
  default     = "spry"
}

variable "database_user" {
  description = "Application database username."
  type        = string
  default     = "spry_app"
}

variable "backend_image" {
  description = "Container image for the Cloud Run API. Override after pushing the app image."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "firebase_site_origin" {
  description = "Firebase Hosting origin allowed by the API's CORS middleware."
  type        = string
  default     = ""
}

variable "cognito_user_pool_id" {
  description = "Existing Cognito user pool ID used to validate API access tokens."
  type        = string
}

variable "cognito_client_id" {
  description = "Existing Cognito app client ID used to validate API access tokens."
  type        = string
}

variable "cognito_region" {
  description = "AWS region containing the Cognito user pool."
  type        = string
  default     = "eu-north-1"
}
