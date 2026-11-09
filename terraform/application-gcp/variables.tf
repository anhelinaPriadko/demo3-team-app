variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
  default     = "europe-west3"
}

variable "zone" {
  type        = string
  description = "GCP zone for all instances"
  default     = "europe-west3-a"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"
  default     = "demo3"
}

variable "vpc_cidr" {
  type        = string
  description = "Overall address space of the application VPC, for reference. Must not overlap 10.10.0.0/16 (management VPC)"
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  type        = string
  description = "Public subnet cidr (Nginx)"
  default     = "10.20.0.0/24"
}

variable "private_subnet_cidr" {
  type        = string
  description = "Private subnet cidr (app and databases)"
  default     = "10.20.1.0/24"
}

variable "app_port" {
  type        = number
  description = "Port the Java application listens on"
  default     = 8080
}

variable "db_data_disk_size" {
  type        = number
  description = "Data disk size in GiB for each PostgreSQL VM"
  default     = 20
}

variable "management_cidr" {
  type        = string
  description = "CIDR of the AWS management VPC, allowed to SSH in over the VPN"
  default     = "10.10.0.0/16"
}

variable "app_instances" {
  type = map(object({
    zone        = string
    internal_ip = optional(string)
  }))
  description = "Application VMs behind Nginx, keyed by name suffix (demo3-<key>). Put them in different zones for redundancy"
  default = {
    "app-1" = { zone = "europe-west3-a", internal_ip = "10.20.1.2" }
    "app-2" = { zone = "europe-west3-b", internal_ip = "10.20.1.5" }
  }
}
