locals {
  roles = toset(["nginx", "app", "db"])

  # Every VM writes logs and metrics
  project_roles = ["roles/logging.logWriter", "roles/monitoring.metricWriter"]

  project_role_bindings = {
    for pair in setproduct(local.roles, local.project_roles) :
    "${pair[0]}/${pair[1]}" => { role_key = pair[0], role = pair[1] }
  }
}

# One service account per role, so no VM uses the default Compute Engine account

resource "google_service_account" "this" {
  for_each = local.roles

  account_id   = "${var.name_prefix}-${each.key}-sa"
  display_name = "${var.name_prefix} ${each.key} instances"
}

resource "google_project_iam_member" "this" {
  for_each = local.project_role_bindings

  project = google_service_account.this[each.value.role_key].project
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.this[each.value.role_key].email}"
}

# Bucket-level access only, never project-wide

resource "google_storage_bucket_iam_member" "app" {
  bucket = var.bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.this["app"].email}"
}

# The db account is limited to the backup path. Note that a conditional binding
# does not cover listing the bucket, only reading and writing objects by name.
resource "google_storage_bucket_iam_member" "db" {
  bucket = var.bucket_name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.this["db"].email}"

  condition {
    title      = "backup-path-only"
    expression = "resource.name.startsWith(\"projects/_/buckets/${var.bucket_name}/objects/${var.db_backup_prefix}\")"
  }
}
