# HA VPN gateway: two interfaces, each with its own public IP

resource "google_compute_ha_vpn_gateway" "this" {
  name    = "${var.name_prefix}-ha-vpn"
  network = var.network
  region  = var.region
}

# Separate from the NAT router in the network module. By default it advertises
# all subnets of the VPC to AWS and learns the AWS VPC CIDR over BGP.

resource "google_compute_router" "this" {
  name    = "${var.name_prefix}-vpn-router"
  network = var.network
  region  = var.region

  bgp {
    asn = var.bgp_asn
  }
}
