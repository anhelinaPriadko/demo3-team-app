output "team_members" {
  description = "Accounts that were granted access"
  value       = sort(tolist(local.members))
}

output "granted_project_roles" {
  description = "Project roles each teammate received"
  value       = local.project_roles
}

output "connect_command" {
  description = "What a teammate runs to connect (replace <vm> with demo3-nginx, demo3-app, demo3-db-master or demo3-db-slave)"
  value       = "gcloud compute ssh <vm> --zone ${var.zone} --project ${var.project_id} --tunnel-through-iap"
}

output "power_commands" {
  description = "What a teammate runs to stop and start a VM (empty when can_power_vms is false)"
  value = var.can_power_vms ? {
    stop  = "gcloud compute instances stop <vm> --zone ${var.zone} --project ${var.project_id}"
    start = "gcloud compute instances start <vm> --zone ${var.zone} --project ${var.project_id}"
  } : {}
}

output "deploy_sa_email" {
  description = "Service account the GitLab runner logs in as"
  value       = google_service_account.deploy.email
}

output "deploy_key_commands" {
  description = "Run by hand with your own account: register the runner's public key, then read the login name"
  value = {
    register_key = "gcloud compute os-login ssh-keys add --key-file=<runner_key>.pub --ttl=0 --impersonate-service-account=${google_service_account.deploy.email}"
    login_name   = "gcloud compute os-login describe-profile --impersonate-service-account=${google_service_account.deploy.email}"
  }
}

output "terraform_sa_email" {
  description = "Service account the runner uses to run Terraform for application-gcp"
  value       = google_service_account.terraform.email
}

output "runner_credential_config_command" {
  description = "Run on the runner (as the user that runs the jobs): writes a credential file with no secrets in it. Point GOOGLE_APPLICATION_CREDENTIALS at it"
  value       = "gcloud iam workload-identity-pools create-cred-config ${google_iam_workload_identity_pool_provider.runner.name} --service-account=${google_service_account.terraform.email} --aws --enable-imdsv2 --output-file=gcp-credentials.json"
}
