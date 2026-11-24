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

variable "witness_zone" {
  type        = string
  description = "GCP zone of the etcd witness"
  default     = "europe-west3-b"
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

variable "app_count" {
  type        = number
  description = "Number of application VMs behind Nginx, named <name_prefix>-app-1, -app-2, ..."
  default     = 2

  validation {
    condition     = var.app_count >= 1 && floor(var.app_count) == var.app_count
    error_message = "app_count must be a whole number of at least 1."
  }
}

variable "app_zones" {
  type        = list(string)
  description = "Zones the app VMs are spread over in turn: index 0 (app-1), 2, 4, ... in the first zone, index 1 (app-2), 3, 5, ... in the second"
  default     = ["europe-west3-a", "europe-west3-b"]

  validation {
    condition     = length(var.app_zones) >= 1
    error_message = "Give at least one zone."
  }
}
