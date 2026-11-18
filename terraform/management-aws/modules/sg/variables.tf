variable "vpc_id" {
  type        = string
  description = "ID of the VPC the security groups belong to"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC cidr, allowed to send OTLP telemetry to SigNoz"
}

variable "additional_otlp_cidrs" {
  type        = list(string)
  description = "Extra CIDRs allowed to send OTLP telemetry to SigNoz, e.g. the GCP application CIDR after the VPN is added"
  default     = []
}

variable "signoz_ui_port" {
  type        = number
  description = "Port the SigNoz UI listens on (8080 in the Docker standalone install)"
  default     = 8080
}
