data "google_compute_subnetwork" "this" {
  self_link = var.subnet_self_link
}

resource "google_compute_address" "internal" {
  count = var.reserve_internal_ip ? 1 : 0

  name         = "${var.name}-internal"
  address_type = "INTERNAL"
  address      = var.internal_ip
  subnetwork   = var.subnet_self_link
  region       = data.google_compute_subnetwork.this.region
}

resource "google_compute_address" "external" {
  count = var.external_ip ? 1 : 0

  name         = "${var.name}-external"
  address_type = "EXTERNAL"
  region       = data.google_compute_subnetwork.this.region
}

resource "google_compute_instance" "this" {
  name         = var.name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = var.network_tags
  labels       = var.labels

  allow_stopping_for_update = true
  metadata_startup_script   = var.startup_script

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = var.boot_disk_size
      type  = "pd-balanced"
    }
  }

  dynamic "attached_disk" {
    for_each = google_compute_disk.data
    content {
      source      = attached_disk.value.id
      device_name = "data"
    }
  }

  network_interface {
    subnetwork = var.subnet_self_link
    network_ip = one(google_compute_address.internal[*].address)

    dynamic "access_config" {
      for_each = google_compute_address.external
      content {
        nat_ip = access_config.value.address
      }
    }
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  # Access through IAP and OS Login, no project SSH keys
  metadata = {
    enable-oslogin = "TRUE"
  }

  lifecycle {
    # A newer "latest" image must not replace a running instance on the next plan
    ignore_changes = [boot_disk[0].initialize_params[0].image]
  }
}

# Optional separate data disk, formatted and mounted by the startup script.
# It is its own resource, so it survives replacement of the instance.

resource "google_compute_disk" "data" {
  count = var.data_disk_size > 0 ? 1 : 0

  name   = "${var.name}-data"
  zone   = var.zone
  size   = var.data_disk_size
  type   = "pd-balanced"
  labels = var.labels
}
