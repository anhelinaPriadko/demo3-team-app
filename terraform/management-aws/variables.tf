variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "availability_zone" {
  type        = string
  description = "Availability zone"
  default     = "eu-central-1a"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC cidr"
  default     = "10.10.0.0/16"
}

variable "private_subnet_cidr" {
  type        = string
  description = "Private subnet cidr"
  default     = "10.10.0.0/24"
}

variable "public_subnet_cidr" {
  type        = string
  description = "Public subnet cidr"
  default     = "10.10.1.0/24"
}

# security group vars


