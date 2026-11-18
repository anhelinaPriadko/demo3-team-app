output "gateway_id" {
  description = "ID of the HA VPN gateway"
  value       = google_compute_ha_vpn_gateway.this.id
}

output "interface_ips" {
  description = "Public IPs of interface 0 and 1. Always two entries, so the AWS side can count them before the gateway exists"
  value       = [for i in [0, 1] : one([for v in google_compute_ha_vpn_gateway.this.vpn_interfaces : v.ip_address if v.id == i])]
}

output "router_name" {
  description = "Name of the Cloud Router that holds the BGP sessions"
  value       = google_compute_router.this.name
}
