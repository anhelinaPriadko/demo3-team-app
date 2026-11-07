output "connection_ids" {
  description = "IDs of the VPN connections"
  value       = aws_vpn_connection.gcp[*].id
}

# Four entries: GCP interface 0 with tunnel 1 and 2, then GCP interface 1 with tunnel 1 and 2.
# The pre-shared keys are kept apart so the rest stays readable.

output "tunnels" {
  description = "AWS endpoint and BGP link addresses of each tunnel"
  value = flatten([
    for i, c in aws_vpn_connection.gcp : [
      {
        gcp_interface      = i
        peer_address       = c.tunnel1_address
        cgw_inside_address = c.tunnel1_cgw_inside_address
        vgw_inside_address = c.tunnel1_vgw_inside_address
      },
      {
        gcp_interface      = i
        peer_address       = c.tunnel2_address
        cgw_inside_address = c.tunnel2_cgw_inside_address
        vgw_inside_address = c.tunnel2_vgw_inside_address
      },
    ]
  ])
}

output "shared_secrets" {
  description = "Pre-shared key of each tunnel, same order as tunnels"
  sensitive   = true
  value = flatten([
    for c in aws_vpn_connection.gcp : [c.tunnel1_preshared_key, c.tunnel2_preshared_key]
  ])
}
