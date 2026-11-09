output "app_1_private_ip" {
  value       = google_compute_instance.app_1.network_interface[0].network_ip
  description = "Private IP address of demo3-app-1"
}