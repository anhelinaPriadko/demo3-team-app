variable "gcp_project_id" {
  type        = string
  description = "GCP Project ID from INFRASTRUCTURE.md"
  default     = "demo3-team1"
}

variable "gcp_region" {
  type        = string
  description = "GCP Region"
  default     = "europe-west3"
}

variable "gcp_zone" {
  type        = string
  description = "GCP Zone"
  default     = "europe-west3-a"
}