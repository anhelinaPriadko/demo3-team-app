variable "name" {
  type        = string
  description = "Bucket name, globally unique (include the project ID)"
}

variable "location" {
  type        = string
  description = "Bucket location (region)"
}

variable "force_destroy" {
  type        = bool
  description = "Delete the bucket with its objects on destroy. Fine for a demo"
  default     = true
}
