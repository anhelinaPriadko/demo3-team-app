output "network_name" {
  description = "Name of the VPC"
  value       = google_compute_network.this.name
}

output "network_self_link" {
  description = "Self link of the VPC"
  value       = google_compute_network.this.self_link
}

output "public_subnet_name" {
  description = "Name of the public subnet"
  value       = google_compute_subnetwork.public.name
}

output "public_subnet_self_link" {
  description = "Self link of the public subnet"
  value       = google_compute_subnetwork.public.self_link
}

output "public_subnet_cidr" {
  description = "CIDR of the public subnet"
  value       = google_compute_subnetwork.public.ip_cidr_range
}

output "private_subnet_name" {
  description = "Name of the private subnet"
  value       = google_compute_subnetwork.private.name
}

output "private_subnet_self_link" {
  description = "Self link of the private subnet"
  value       = google_compute_subnetwork.private.self_link
}

output "private_subnet_cidr" {
  description = "CIDR of the private subnet"
  value       = google_compute_subnetwork.private.ip_cidr_range
}
