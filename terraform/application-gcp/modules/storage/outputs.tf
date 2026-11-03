output "bucket_name" {
  description = "Name of the bucket"
  value       = google_storage_bucket.this.name
}
