# Latest Ubuntu 24.04 LTS from Canonical, resolved when the instance is created
data "google_compute_image" "ubuntu" {
  family  = var.image_family
  project = var.image_project
}
