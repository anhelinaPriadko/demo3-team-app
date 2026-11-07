# The four AWS tunnel endpoints seen as one peer gateway
resource "google_compute_external_vpn_gateway" "aws" {
  name            = "${var.name_prefix}-aws-peer"
  redundancy_type = "FOUR_IPS_REDUNDANCY"
  description     = "AWS Site-to-Site VPN endpoints"

  dynamic "interface" {
    for_each = var.tunnels
    content {
      id         = interface.key
      ip_address = interface.value.peer_address
    }
  }
}

resource "google_compute_vpn_tunnel" "this" {
  count = length(var.tunnels)

  name   = "${var.name_prefix}-aws-tunnel-${count.index}"
  region = var.region

  vpn_gateway                     = var.gateway_id
  vpn_gateway_interface           = var.tunnels[count.index].gcp_interface
  peer_external_gateway           = google_compute_external_vpn_gateway.aws.id
  peer_external_gateway_interface = count.index
  shared_secret                   = var.shared_secrets[count.index]
  router                          = var.router_name
  ike_version                     = 2
}

# One BGP session per tunnel, over the /30 link-local range AWS assigned

resource "google_compute_router_interface" "this" {
  count = length(var.tunnels)

  name       = "${var.name_prefix}-aws-if-${count.index}"
  router     = var.router_name
  region     = var.region
  ip_range   = "${var.tunnels[count.index].cgw_inside_address}/30"
  vpn_tunnel = google_compute_vpn_tunnel.this[count.index].name
}

resource "google_compute_router_peer" "this" {
  count = length(var.tunnels)

  name            = "${var.name_prefix}-aws-peer-${count.index}"
  router          = var.router_name
  region          = var.region
  interface       = google_compute_router_interface.this[count.index].name
  ip_address      = var.tunnels[count.index].cgw_inside_address
  peer_ip_address = var.tunnels[count.index].vgw_inside_address
  peer_asn        = var.aws_bgp_asn
}
