# Rules match by network tag, which the compute module sets: web (Nginx), app, db, etcd (witness).
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

# 2379 etcd client, 2380 etcd peer, 8008 Patroni REST API (health checks)
resource "google_compute_firewall" "etcd_patroni" {
  name      = "${var.name_prefix}-allow-etcd-patroni"
  network   = var.network
  direction = "INGRESS"

  source_tags = ["db", "etcd"]
  target_tags = ["db", "etcd"]

  allow {
    protocol = "tcp"
    ports    = ["2379", "2380", "8008"]
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

# Management VPC over the VPN: SSH for pipeline deployments, ICMP for connectivity tests

resource "google_compute_firewall" "ssh_from_management" {
  count = var.management_cidr != null ? 1 : 0

  name      = "${var.name_prefix}-allow-ssh-from-management"
  network   = var.network
  direction = "INGRESS"

  source_ranges = [var.management_cidr]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "icmp_from_management" {
  count = var.management_cidr != null ? 1 : 0

  name      = "${var.name_prefix}-allow-icmp-from-management"
  network   = var.network
  direction = "INGRESS"

  source_ranges = [var.management_cidr]

  allow {
    protocol = "icmp"
  }
}
