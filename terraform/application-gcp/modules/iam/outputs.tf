output "nginx_sa_email" {
  description = "Email of the Nginx service account"
  value       = google_service_account.this["nginx"].email
}

output "app_sa_email" {
  description = "Email of the app service account"
  value       = google_service_account.this["app"].email
}

output "db_sa_email" {
  description = "Email of the database service account"
  value       = google_service_account.this["db"].email
}

output "etcd_sa_email" {
  description = "Email of the etcd witness service account (logs and metrics only)"
  value       = google_service_account.this["etcd"].email
}
