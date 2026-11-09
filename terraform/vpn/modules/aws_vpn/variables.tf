variable "name_prefix" {
  type        = string
  description = "Prefix for resource names, e.g. demo3"
}

variable "vpc_id" {
  type        = string
  description = "ID of the management VPC"
}

variable "private_route_table_id" {
  type        = string
  description = "Private route table that learns the GCP routes over BGP"
}

variable "amazon_side_asn" {
  type        = number
  description = "BGP ASN of the virtual private gateway"
}

variable "gcp_bgp_asn" {
  type        = number
  description = "BGP ASN of the GCP Cloud Router"
}

variable "gcp_gateway_ips" {
  type        = list(string)
  description = "Public IPs of the GCP HA VPN interfaces. One VPN connection is created per IP"
}

variable "tunnel_inside_cidrs" {
  type        = list(string)
  description = "One /30 link-local range per tunnel, two per VPN connection, in order"
}
