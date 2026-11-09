variable "name_prefix" {
  type        = string
  description = "Prefix for resource names, e.g. demo3"
}

variable "region" {
  type        = string
  description = "Region of the tunnels and BGP sessions"
}

variable "gateway_id" {
  type        = string
  description = "ID of the HA VPN gateway"
}

variable "router_name" {
  type        = string
  description = "Name of the Cloud Router"
}

variable "aws_bgp_asn" {
  type        = number
  description = "BGP ASN of the AWS virtual private gateway"
}

variable "tunnels" {
  type = list(object({
    gcp_interface      = number
    peer_address       = string
    cgw_inside_address = string
    vgw_inside_address = string
  }))
  description = "The AWS tunnel endpoints, four of them"
}

variable "shared_secrets" {
  type        = list(string)
  description = "Pre-shared key of each tunnel, same order as tunnels"
  sensitive   = true
}
