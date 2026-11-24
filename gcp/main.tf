locals {
  required_apis = toset([
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "firebase.googleapis.com",
    "firebasehosting.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
    "sqladmin.googleapis.com",
  ])
  cloud_sql_connection_name = google_sql_database_instance.app.connection_name
  firebase_origin           = var.firebase_site_origin != "" ? var.firebase_site_origin : "https://${var.project_id}.web.app"
}

resource "google_project_service" "required" {
  for_each = local.required_apis

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "containers" {
  depends_on = [google_project_service.required]

  location      = var.region
  repository_id = "${var.name_prefix}-containers"
  description   = "Container images for the Spry application"
  format        = "DOCKER"
}

resource "random_password" "database" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "google_secret_manager_secret" "database_password" {
  depends_on = [google_project_service.required]

  secret_id = "${var.name_prefix}-database-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "database_password" {
  secret      = google_secret_manager_secret.database_password.id
  secret_data = random_password.database.result
}

resource "google_sql_database_instance" "app" {
  depends_on = [google_project_service.required]

  name                = "${var.name_prefix}-postgres"
  region              = var.region
  database_version    = "POSTGRES_16"
  deletion_protection = false

  settings {
    tier              = "db-f1-micro"
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 10
    disk_autoresize   = false

    backup_configuration {
      enabled = false
    }

    ip_configuration {
      ipv4_enabled = true
      ssl_mode     = "ENCRYPTED_ONLY"
    }
  }
}

resource "google_sql_database" "app" {
  name     = var.database_name
  instance = google_sql_database_instance.app.name
}

resource "google_sql_user" "app" {
  name     = var.database_user
  instance = google_sql_database_instance.app.name
  password = random_password.database.result
}

resource "google_service_account" "api" {
  account_id   = "${var.name_prefix}-api"
  display_name = "Spry Cloud Run API"
}

resource "google_project_iam_member" "api_cloud_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.api.email}"
}

resource "google_secret_manager_secret_iam_member" "api_database_password" {
  secret_id = google_secret_manager_secret.database_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

resource "google_cloud_run_v2_service" "api" {
  depends_on = [
    google_project_service.required,
    google_sql_database.app,
    google_sql_user.app,
    google_project_iam_member.api_cloud_sql_client,
    google_secret_manager_secret_iam_member.api_database_password,
  ]

  name                = "${var.name_prefix}-api"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account                  = google_service_account.api.email
    max_instance_request_concurrency = 40

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [local.cloud_sql_connection_name]
      }
    }

    containers {
      image = var.backend_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = true
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      env {
        name  = "DB_HOST"
        value = "/cloudsql/${local.cloud_sql_connection_name}"
      }

      env {
        name  = "DB_PORT"
        value = "5432"
      }

      env {
        name  = "DB_NAME"
        value = google_sql_database.app.name
      }

      env {
        name  = "DB_USER"
        value = google_sql_user.app.name
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_password.secret_id
            version = "latest"
          }
        }
      }

      env {
        name  = "CORS_ORIGINS"
        value = local.firebase_origin
      }

      env {
        name  = "COGNITO_USER_POOL_ID"
        value = var.cognito_user_pool_id
      }

      env {
        name  = "COGNITO_CLIENT_ID"
        value = var.cognito_client_id
      }

      env {
        name  = "AWS_REGION"
        value = var.cognito_region
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "firebase_invoker" {
  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
