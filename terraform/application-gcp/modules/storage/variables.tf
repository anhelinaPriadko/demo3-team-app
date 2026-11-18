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

variable "app_sa_email" {
  type        = string
  description = "Email of the app service account, gets objectAdmin on the bucket"
}

variable "db_sa_email" {
  type        = string
  description = "Email of the database service account, gets objectAdmin on the bucket (backups)"
}
