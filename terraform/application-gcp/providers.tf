provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  user_project_override = true

  default_labels = {
    project = "demo3"
  }
}