output "gcp_vpn_gateway_ips" {
  description = "Public IPs of the two GCP HA VPN interfaces"
  value       = module.gcp_gateway.interface_ips
}

output "aws_vpn_connection_ids" {
  description = "IDs of the AWS Site-to-Site VPN connections"
  value       = module.aws_vpn.connection_ids
}

output "check_commands" {
  description = "Commands to check that the tunnels and BGP sessions are up"
  value = {
    gcp_tunnels = "gcloud compute vpn-tunnels list --project ${var.project_id} --filter=region:${var.gcp_region}"
    gcp_bgp     = "gcloud compute routers get-status ${module.gcp_gateway.router_name} --region ${var.gcp_region} --project ${var.project_id}"
    aws_tunnels = "aws ec2 describe-vpn-connections --region ${var.aws_region} --query 'VpnConnections[].VgwTelemetry[].[OutsideIpAddress,Status,StatusMessage]' --output table"
  }
}
