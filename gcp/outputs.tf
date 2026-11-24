output "artifact_registry_repository" {
  description = "Docker repository for the Cloud Run backend image."
  value       = google_artifact_registry_repository.containers.name
}

output "backend_image_base" {
  description = "Artifact Registry path to use when tagging the backend image."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.containers.repository_id}/api"
}

output "cloud_run_url" {
  description = "Public Cloud Run service URL. The API still validates Cognito access tokens."
  value       = google_cloud_run_v2_service.api.uri
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name for Cloud Run or Cloud SQL Auth Proxy."
  value       = google_sql_database_instance.app.connection_name
}

output "firebase_hosting_origin" {
  description = "Expected default Firebase Hosting origin."
  value       = local.firebase_origin
}
