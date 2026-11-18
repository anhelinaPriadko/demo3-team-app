variable "name_prefix" {
  type        = string
  description = "Prefix for resource names, e.g. demo3"
}

variable "region" {
  type        = string
  description = "Region of the subnets, router and NAT"
}

variable "public_subnet_cidr" {
  type        = string
  description = "Public subnet cidr (Nginx)"
}

variable "private_subnet_cidr" {
  type        = string
  description = "Private subnet cidr (app and databases)"
}
