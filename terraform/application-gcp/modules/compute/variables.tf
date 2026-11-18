variable "name" {
  type        = string
  description = "Instance name, e.g. demo3-app"
}

variable "machine_type" {
  type        = string
  description = "Compute Engine machine type"
}

variable "zone" {
  type        = string
  description = "Zone of the instance and its data disk"
}

variable "subnet_self_link" {
  type        = string
  description = "Self link of the subnet to attach the instance to"
}

variable "network_tags" {
  type        = list(string)
  description = "Network tags the firewall rules match on (web, app, db)"
}

variable "service_account_email" {
  type        = string
  description = "Service account the instance runs as"
}

variable "image_family" {
  type        = string
  description = "Image family used when the instance is created"
  default     = "ubuntu-2404-lts-amd64"
}

variable "image_project" {
  type        = string
  description = "Project that owns the image family"
  default     = "ubuntu-os-cloud"
}

variable "boot_disk_size" {
  type        = number
  description = "Boot disk size in GiB"
  default     = 15
}

variable "data_disk_size" {
  type        = number
  description = "Size in GiB of an extra data disk attached as device name data. 0 means no data disk"
  default     = 0
}

variable "reserve_internal_ip" {
  type        = bool
  description = "Reserve a static internal IP, so other VMs can use a fixed address"
  default     = false
}

variable "internal_ip" {
  type        = string
  description = "Fixed internal IP to reserve. When null, GCP picks one. Only used with reserve_internal_ip"
  default     = null
}

variable "external_ip" {
  type        = bool
  description = "Give the instance a reserved static external IP"
  default     = false
}

variable "startup_script" {
  type        = string
  description = "Startup script, runs on every boot"
  default     = null
}

variable "labels" {
  type        = map(string)
  description = "Extra labels added to the instance and its data disk"
  default     = {}
}
