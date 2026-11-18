# A VPC is global and a subnet is regional. A VM is public only if it has an external IP.

resource "google_compute_network" "this" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "public" {
  name          = "${var.name_prefix}-public"
  network       = google_compute_network.this.id
  region        = var.region
  ip_cidr_range = var.public_subnet_cidr
}

resource "google_compute_subnetwork" "private" {
  name          = "${var.name_prefix}-private"
  network       = google_compute_network.this.id
  region        = var.region
  ip_cidr_range = var.private_subnet_cidr

  # Reach Cloud Storage and other Google APIs without NAT
  private_ip_google_access = true
}

# Outbound internet for the private VMs (package installs, GitHub, updates)

resource "google_compute_router" "this" {
  name    = "${var.name_prefix}-router"
  network = google_compute_network.this.id
  region  = var.region
}

resource "google_compute_router_nat" "this" {
  name                               = "${var.name_prefix}-nat"
  router                             = google_compute_router.this.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}
