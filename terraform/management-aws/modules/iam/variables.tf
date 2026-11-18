variable "name_prefix" {
  type        = string
  description = "Prefix for role, profile and policy names"
  default     = "demo3"
}

variable "gitlab_secrets_path" {
  type        = string
  description = "SSM Parameter Store path prefix holding the repo sync secrets. The GitLab role can read only parameters under it"
  default     = "/demo3/gitlab-sync"

  validation {
    condition     = startswith(var.gitlab_secrets_path, "/") && !endswith(var.gitlab_secrets_path, "/")
    error_message = "The path must start with / and must not end with /, for example /demo3/gitlab-sync."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the customer managed KMS key that encrypts the sync secrets. Leave null when using the default aws/ssm key"
  default     = null
}
