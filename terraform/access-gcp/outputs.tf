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

output "vm_sa_emails" {
  description = "VM service accounts by role, used by application-gcp"
  value       = { for k, sa in google_service_account.vm : k => sa.email }
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

output "dns_name_servers" {
  description = "Name servers of the public zone, without the trailing dot. Set these at your domain registrar"
  value       = [for ns in google_dns_managed_zone.public.name_servers : trimsuffix(ns, ".")]
}

output "dns_zone_name" {
  description = "Name of the Cloud DNS zone, used by application-gcp to add records"
  value       = google_dns_managed_zone.public.name
}

output "db_secret_ids" {
  description = "Secret Manager IDs of the database credentials, readable by demo3-db-sa"
  value       = { for k, s in google_secret_manager_secret.db : k => s.secret_id }
}

output "db_secret_add_commands" {
  description = "Run by hand once to set each value"
  value = {
    for k, s in google_secret_manager_secret.db :
    k => "printf '%s' '<value>' | gcloud secrets versions add ${s.secret_id} --project ${var.project_id} --data-file=-"
  }
}
