variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "aws_region" {
  type        = string
  description = "AWS region of the management VPC"
  default     = "eu-central-1"
}

variable "gcp_region" {
  type        = string
  description = "GCP region of the application VPC. Must match the application-gcp root"
  default     = "europe-west3"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"
  default     = "demo3"
}

variable "aws_bgp_asn" {
  type        = number
  description = "BGP ASN of the AWS virtual private gateway"
  default     = 64512
}

variable "gcp_bgp_asn" {
  type        = number
  description = "BGP ASN of the GCP Cloud Router. Must differ from aws_bgp_asn"
  default     = 65020
}
