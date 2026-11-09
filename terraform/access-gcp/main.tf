# Access for the teammates: connect to the VMs through IAP with OS Login.
# Applied by hand with your own credentials, not by the application pipeline.
# The VM service accounts come from application-gcp, so apply that root first.

locals {
  members = toset([for email in var.team_emails : "user:${email}"])

  login_role = var.can_sudo ? "roles/compute.osAdminLogin" : "roles/compute.osLogin"

  project_roles = [
    "roles/iap.tunnelResourceAccessor", # open the IAP tunnel
    local.login_role,                   # OS Login on the VMs
    "roles/compute.viewer",             # look up instances by name and zone
  ]

  project_bindings = {
    for pair in setproduct(local.members, local.project_roles) :
    "${pair[0]}/${pair[1]}" => { member = pair[0], role = pair[1] }
  }

  sa_bindings = {
    for pair in setproduct(local.members, var.vm_service_accounts) :
    "${pair[0]}/${pair[1]}" => { member = pair[0], sa = pair[1] }
  }
}

# Additive bindings (_member), so no existing grant on these roles is touched
resource "google_project_iam_member" "team" {
  for_each = local.project_bindings

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}

# OS Login to a VM that runs as a service account also needs serviceAccountUser
# on that account. Bound on the three VM accounts only, never project-wide.
resource "google_service_account_iam_member" "team_use" {
  for_each = local.sa_bindings

  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.name_prefix}-${each.value.sa}-sa@${var.project_id}.iam.gserviceaccount.com"
  role               = "roles/iam.serviceAccountUser"
  member             = each.value.member
}

# Power on and off. Only start and stop are granted here: looking up the instance and
# waiting for the operation to finish come from roles/compute.viewer above.
# Limited by condition to the demo3-* instances, so other VMs in the project stay untouched.

resource "google_project_iam_custom_role" "vm_power" {
  count = var.can_power_vms ? 1 : 0

  role_id     = "${var.name_prefix}VmPower"
  title       = "${var.name_prefix} VM power"
  description = "Start and stop Compute Engine instances"
  permissions = [
    "compute.instances.start",
    "compute.instances.stop",
  ]
}

resource "google_project_iam_member" "team_power" {
  for_each = var.can_power_vms ? local.members : toset([])

  project = var.project_id
  role    = google_project_iam_custom_role.vm_power[0].id
  member  = each.value

  condition {
    title       = "${var.name_prefix}-instances-only"
    description = "Only instances named ${var.name_prefix}-*"
    expression  = join(" || ", [for z in var.vm_zones : "resource.name.startsWith(\"projects/${var.project_id}/zones/${z}/instances/${var.name_prefix}-\")"])
  }
}

# Deploy identity for the GitLab runner on AWS. A service account, not a Google user:
# the runner holds only an SSH private key. Its public key is added to this account's
# OS Login profile by hand (see outputs), so no service account key is ever created.

resource "google_service_account" "deploy" {
  account_id   = "${var.name_prefix}-deploy-sa"
  display_name = "${var.name_prefix} deploy (GitLab runner over SSH)"
}

resource "google_project_iam_member" "deploy_login" {
  project = var.project_id
  role    = var.deploy_can_sudo ? "roles/compute.osAdminLogin" : "roles/compute.osLogin"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

# Same as for the teammates: needed to log in to VMs that run as a service account
resource "google_service_account_iam_member" "deploy_use" {
  for_each = toset(var.vm_service_accounts)

  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.name_prefix}-${each.value}-sa@${var.project_id}.iam.gserviceaccount.com"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deploy.email}"
}

# Terraform identity for the GitLab runner on AWS: creates and changes the application
# infrastructure (the application-gcp root). The runner has no GCP key. Its AWS instance
# role is trusted through Workload Identity Federation and exchanged for short-lived
# tokens of the service account below.

resource "google_project_service" "sts" {
  project            = var.project_id
  service            = "sts.googleapis.com"
  disable_on_destroy = false
}

resource "google_service_account" "terraform" {
  account_id   = "${var.name_prefix}-terraform-sa"
  display_name = "${var.name_prefix} terraform (GitLab runner, application infrastructure)"
}

locals {
  # What application-gcp creates: network, firewall, VMs, disks, addresses, service accounts, bucket.
  # compute.admin and storage.admin also cover reading and writing the state bucket.
  terraform_roles = [
    "roles/compute.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser", # attach the VM service accounts to the VMs
    "roles/storage.admin",
  ]

  # application-gcp grants these roles to the VM service accounts and nothing else
  grantable_roles = ["roles/logging.logWriter", "roles/monitoring.metricWriter"]
}

resource "google_project_iam_member" "terraform" {
  for_each = toset(local.terraform_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

# Project IAM admin lets an account grant itself anything, so it is limited by condition
# to handing out only the roles above. Reading the policy is not restricted.
resource "google_project_iam_member" "terraform_iam_admin" {
  project = var.project_id
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = "serviceAccount:${google_service_account.terraform.email}"

  condition {
    title      = "grant-vm-logging-roles-only"
    expression = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([${join(",", [for r in local.grantable_roles : "'${r}'"])}])"
  }
}

resource "google_iam_workload_identity_pool" "aws" {
  workload_identity_pool_id = "${var.name_prefix}-aws"
  display_name              = "${var.name_prefix} AWS"

  depends_on = [google_project_service.sts]
}

# Only the runner's role in our AWS account is accepted, any other AWS identity is refused
resource "google_iam_workload_identity_pool_provider" "runner" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.aws.workload_identity_pool_id
  workload_identity_pool_provider_id = "aws-runner"
  display_name                       = "AWS runner role"

  attribute_mapping = {
    "google.subject"        = "assertion.arn"
    "attribute.aws_role"    = "assertion.arn.extract('assumed-role/{role}/')"
    "attribute.aws_account" = "assertion.account"
  }
  attribute_condition = "assertion.arn.startsWith('arn:aws:sts::${var.aws_account_id}:assumed-role/${var.runner_aws_role}/')"

  aws {
    account_id = var.aws_account_id
  }
}

resource "google_service_account_iam_member" "terraform_federation" {
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.aws.name}/attribute.aws_role/${var.runner_aws_role}"
}
