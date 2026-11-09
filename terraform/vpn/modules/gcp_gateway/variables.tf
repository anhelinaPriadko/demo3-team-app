variable "name_prefix" {
  type        = string
  description = "Prefix for resource names, e.g. demo3"
}

variable "region" {
  type        = string
  description = "Region of the gateway and Cloud Router"
}

variable "network" {
  type        = string
  description = "Self link of the application VPC"
}

variable "bgp_asn" {
  type        = number
  description = "BGP ASN of the Cloud Router"
}
