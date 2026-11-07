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
  description = "Zone used in the connect and power commands in the outputs"
  default     = "europe-west3-a"
}

variable "name_prefix" {
  type        = string
  description = "Prefix used for the VM service accounts, must match application-gcp"
  default     = "demo3"
}

variable "team_emails" {
  type        = list(string)
  description = "Google account emails of the teammates who may connect to the VMs"
  default     = []

  validation {
    condition     = alltrue([for e in var.team_emails : can(regex("^[^@\\s]+@[^@\\s]+$", e))])
    error_message = "Every entry must be an email address, for example anna@gmail.com."
  }
}

variable "vm_service_accounts" {
  type        = list(string)
  description = "Roles of the VM service accounts created by application-gcp (<name_prefix>-<role>-sa). They must already exist when this root is applied"
  default     = ["nginx", "app", "db"]
}

variable "can_sudo" {
  type        = bool
  description = "true gives roles/compute.osAdminLogin (root on the VMs), false gives roles/compute.osLogin"
  default     = true
}

variable "can_power_vms" {
  type        = bool
  description = "true lets the teammates start and stop the <name_prefix>-* VMs"
  default     = true
}

variable "deploy_can_sudo" {
  type        = bool
  description = "true gives the deploy service account roles/compute.osAdminLogin (sudo on the VMs), false gives roles/compute.osLogin"
  default     = false
}

variable "aws_account_id" {
  type        = string
  description = "ID of the AWS account that holds the GitLab runner"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "The AWS account ID is 12 digits."
  }
}

variable "runner_aws_role" {
  type        = string
  description = "Name of the runner's AWS instance role, the only AWS identity trusted to use the Terraform service account"
  default     = "demo3-runner"
}

variable "vm_zones" {
  type        = list(string)
  description = "Zones the demo3-* VMs run in. The start/stop permission is granted for these zones only, so add a zone here when a VM is placed in a new one"
  default     = ["europe-west3-a", "europe-west3-b"]
}
