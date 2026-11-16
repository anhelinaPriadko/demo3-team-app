# Identities for the application VMs, plus access for the teammates, the deploy account
# and the Terraform account. Applied by hand before application-gcp

# VM service accounts: one per VM role.

locals {
  vm_roles = toset(["nginx", "app", "db", "etcd"])
}

resource "google_service_account" "vm" {
  for_each = local.vm_roles

  account_id   = "${var.name_prefix}-${each.key}-sa"
  display_name = "${var.name_prefix} ${each.key} instances"
}

# Access for the teammates: connect to the VMs through IAP with OS Login.

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
    for pair in setproduct(local.members, local.vm_roles) :
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
# on that account. Bound on the VM accounts only, never project-wide.
resource "google_service_account_iam_member" "team_use" {
  for_each = local.sa_bindings

  service_account_id = google_service_account.vm[each.value.sa].name
  role               = "roles/iam.serviceAccountUser"
  member             = each.value.member
}

# Power on and off.

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

resource "google_project_iam_member" "team_power_primary_zone" {
  for_each = local.members

  project = var.project_id
  role    = google_project_iam_custom_role.vm_power[0].id
  member  = each.key

  condition {
    title       = "${var.name_prefix}-instances-only"
    description = "Only instances named ${var.name_prefix}-*"
    expression  = "resource.name.startsWith(\"projects/${var.project_id}/zones/${var.vm_zone_primary}/instances/${var.name_prefix}-\")"
  }
}

resource "google_project_iam_member" "team_power_secondary_zone" {
  for_each = local.members

  project = var.project_id
  role    = google_project_iam_custom_role.vm_power[0].id
  member  = each.key

  condition {
    title       = "${var.name_prefix}-instances-only"
    description = "Only instances named ${var.name_prefix}-*"
    expression  = "resource.name.startsWith(\"projects/${var.project_id}/zones/${var.vm_zone_secondary}/instances/${var.name_prefix}-\")"
  }
}

# Deploy identity for the GitLab runner on AWS.

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
  for_each = local.vm_roles

  service_account_id = google_service_account.vm[each.key].name
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
  # What application-gcp creates: network, firewall, VMs, disks, addresses, bucket and its IAM.
  # compute.admin and storage.admin also cover reading and writing the state bucket.
  terraform_roles = [
    "roles/compute.admin",
    "roles/storage.admin",
  ]
}

resource "google_project_iam_member" "terraform" {
  for_each = toset(local.terraform_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

# Attach the VM service accounts to VMs (and read them). Bound on these accounts only,
# so the pipeline cannot run a VM as any other account in the project.
resource "google_service_account_iam_member" "terraform_use" {
  for_each = local.vm_roles

  service_account_id = google_service_account.vm[each.key].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.terraform.email}"
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

# Public DNS zone for the domain. It lives here and not in application-gcp, so its name
# servers stay the same when the application is destroyed and rebuilt.

resource "google_project_service" "dns" {
  project            = var.project_id
  service            = "dns.googleapis.com"
  disable_on_destroy = false
}

resource "google_dns_managed_zone" "public" {
  name        = "${var.name_prefix}-public"
  dns_name    = "${trimsuffix(var.domain_name, ".")}."
  description = "Public zone for ${var.domain_name}"

  depends_on = [google_project_service.dns]
}

# Lets the pipeline manage records in this zone only, not other zones or project DNS settings
resource "google_dns_managed_zone_iam_member" "terraform_records" {
  project      = var.project_id
  managed_zone = google_dns_managed_zone.public.name
  role         = "roles/dns.admin"
  member       = "serviceAccount:${google_service_account.terraform.email}"
}
