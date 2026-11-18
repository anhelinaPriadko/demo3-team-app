locals {
  aws = data.terraform_remote_state.aws.outputs
  gcp = data.terraform_remote_state.gcp.outputs

  # Two AWS VPN connections with two tunnels each, one pair per GCP HA VPN interface.
  # Each tunnel gets a /30 link-local range for BGP (AWS: first address, GCP: second).
  tunnel_inside_cidrs = [
    "169.254.10.0/30",
    "169.254.11.0/30",
    "169.254.12.0/30",
    "169.254.13.0/30",
  ]
}

check "same_gcp_region" {
  assert {
    condition     = var.gcp_region == local.gcp.region
    error_message = "gcp_region (${var.gcp_region}) differs from the application-gcp root (${local.gcp.region})."
  }
}

module "gcp_gateway" {
  source = "./modules/gcp_gateway"

  name_prefix = var.name_prefix
  region      = var.gcp_region
  network     = local.gcp.network_self_link
  bgp_asn     = var.gcp_bgp_asn
}

module "aws_vpn" {
  source = "./modules/aws_vpn"

  name_prefix            = var.name_prefix
  vpc_id                 = local.aws.vpc_id
  private_route_table_id = local.aws.private_route_table_id
  amazon_side_asn        = var.aws_bgp_asn
  gcp_bgp_asn            = var.gcp_bgp_asn
  gcp_gateway_ips        = module.gcp_gateway.interface_ips
  tunnel_inside_cidrs    = local.tunnel_inside_cidrs
}

module "gcp_tunnels" {
  source = "./modules/gcp_tunnels"

  name_prefix    = var.name_prefix
  region         = var.gcp_region
  gateway_id     = module.gcp_gateway.gateway_id
  router_name    = module.gcp_gateway.router_name
  aws_bgp_asn    = var.aws_bgp_asn
  tunnels        = module.aws_vpn.tunnels
  shared_secrets = module.aws_vpn.shared_secrets
}
