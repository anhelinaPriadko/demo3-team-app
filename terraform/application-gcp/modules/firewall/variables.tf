variable "name_prefix" {
  type        = string
  description = "Prefix for rule names, e.g. demo3"
}

variable "network" {
  type        = string
  description = "Name or self link of the VPC the rules belong to"
}

variable "app_port" {
  type        = number
  description = "Port the Java application listens on"
}

variable "iap_source_range" {
  type        = string
  description = "Source range of IAP TCP forwarding"
  default     = "35.235.240.0/20"
}
