variable "availability_zone" {
  type        = string
  description = "Availability zone for EC2"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC cidr"
}

variable "private_subnet_cidr" {
  type        = string
  description = "Private subnet cidr"
}

variable "public_subnet_cidr" {
  type        = string
  description = "Public subnet cidr"
}

