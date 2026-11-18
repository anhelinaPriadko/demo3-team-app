resource "google_storage_bucket" "this" {
  name          = var.name
  location      = var.location
  force_destroy = var.force_destroy

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }
}

# Bucket-level access only, never project-wide. The service accounts are managed in access-gcp.

resource "google_storage_bucket_iam_member" "app" {
  bucket = google_storage_bucket.this.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.app_sa_email}"
}

resource "google_storage_bucket_iam_member" "db" {
  bucket = google_storage_bucket.this.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.db_sa_email}"
}
