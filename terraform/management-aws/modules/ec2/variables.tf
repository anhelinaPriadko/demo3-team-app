variable "name" {
  type        = string
  description = "Name tag of the instance, e.g. demo3-gitlab"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
}

variable "subnet_id" {
  type        = string
  description = "ID of the subnet to launch the instance in (private subnet)"
}

variable "availability_zone" {
  type = string
  description = "Subnet availability zone"
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs attached to the instance"
}

variable "iam_instance_profile" {
  type        = string
  description = "Name of the IAM instance profile (needs AmazonSSMManagedInstanceCore for Session Manager)"
}

variable "ami_id" {
  type        = string
  description = "AMI ID. When null, the latest Ubuntu 24.04 LTS amd64 AMI from Canonical is used"
  default     = null
}

variable "root_volume_size" {
  type        = number
  description = "Root volume size in GiB"
  default     = 15
}

variable "data_volume_size" {
  type        = number
  description = "Size in GiB of an extra data volume attached at /dev/sdf. 0 means no data volume"
  default     = 0
}

variable "user_data" {
  type        = string
  description = "User data script run at first boot"
  default     = null
}

variable "metadata_hop_limit" {
  type        = number
  description = "IMDS hop limit. 1 keeps containers from reading the instance role credentials, use 2 if containers on the instance need them"
  default     = 1
}

variable "tags" {
  type        = map(string)
  description = "Extra tags added to the instance and its data volume"
  default     = {}
}
