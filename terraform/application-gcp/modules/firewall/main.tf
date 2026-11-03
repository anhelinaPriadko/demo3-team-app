# Rules match by network tag, which the compute module sets: web (Nginx), app, db.
# Ingress is denied by default and egress is allowed by default.

resource "google_compute_firewall" "web_from_internet" {
  name      = "${var.name_prefix}-allow-web-from-internet"
  network   = var.network
  direction = "INGRESS"

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

resource "google_compute_firewall" "app_from_web" {
  name      = "${var.name_prefix}-allow-app-from-web"
  network   = var.network
  direction = "INGRESS"

  source_tags = ["web"]
  target_tags = ["app"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.app_port)]
  }
}

resource "google_compute_firewall" "db_from_app" {
  name      = "${var.name_prefix}-allow-db-from-app"
  network   = var.network
  direction = "INGRESS"

  source_tags = ["app"]
  target_tags = ["db"]

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }
}

# Replication between master and slave, one rule covers both directions
resource "google_compute_firewall" "db_replication" {
  name      = "${var.name_prefix}-allow-db-replication"
  network   = var.network
  direction = "INGRESS"

  source_tags = ["db"]
  target_tags = ["db"]

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }
}

resource "google_compute_firewall" "iap_ssh" {
  name      = "${var.name_prefix}-allow-iap-ssh"
  network   = var.network
  direction = "INGRESS"

  source_ranges = [var.iap_source_range]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
