variable "name_prefix" {
  type        = string
  description = "Prefix for service account IDs, e.g. demo3"
}

variable "bucket_name" {
  type        = string
  description = "Name of the application bucket the app and db accounts get access to"
}

variable "db_backup_prefix" {
  type        = string
  description = "Object path prefix in the bucket the db account is limited to"
  default     = "backups/"
}
