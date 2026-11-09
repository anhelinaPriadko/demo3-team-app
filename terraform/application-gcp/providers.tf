provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  default_labels = {
    project = "demo3"
  }
}
