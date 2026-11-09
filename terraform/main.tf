terraform {
  required_version = ">= 1.0.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "demo3-tfstate-gcp"
    prefix = "demo3/application"
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone    = var.gcp_zone
}

resource "google_compute_instance" "app_1" {
  name         = "demo3-app-1"
  machine_type = "e2-medium"
  zone         = var.gcp_zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts"
      size  = 15
    }
  }

  network_interface {
    subnetwork = "projects/demo3-team1/regions/europe-west3/subnetworks/demo3-vpc-private"
    network_ip = "10.20.1.2"
  }

  service_account {
    email  = "demo3-app-sa@demo3-team1.iam.gserviceaccount.com"
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}