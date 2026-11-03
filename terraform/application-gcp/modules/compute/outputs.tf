output "name" {
  description = "Instance name, used to connect through IAP"
  value       = google_compute_instance.this.name
}

output "private_ip" {
  description = "Internal IP address of the instance"
  value       = google_compute_instance.this.network_interface[0].network_ip
}

output "public_ip" {
  description = "Reserved external IP address, null when the instance has none"
  value       = one(google_compute_address.external[*].address)
}
