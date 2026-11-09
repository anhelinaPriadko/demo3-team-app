# access-gcp

Terraform root that controls who and what can access the GCP application project: the team's access to the VMs, the identity the GitLab runner uses to deploy, and the identity it uses to run Terraform. It manages access only and creates no infrastructure.

State: GCS bucket `demo3-tfstate-gcp`, prefix `demo3/access`.

## Role in the platform

This root is applied after `application-gcp`, whose VM service accounts it references. It is run by a project administrator with their own credentials, not by the pipeline: the pipeline's service account cannot change access. Runner setup is described in [RUNNER_SETUP.md](RUNNER_SETUP.md).

## Team access

Every address in `team_emails` gets the same access.

| Action | Command |
|---|---|
| Connect to a VM | `gcloud compute ssh <vm> --zone <zone> --project demo3-team1 --tunnel-through-iap` |
| Start or stop a VM | `gcloud compute instances start\|stop <vm> --zone <zone> --project demo3-team1` |

This applies to `demo3-nginx`, `demo3-app-1`, `demo3-app-2`, `demo3-db-master` and `demo3-db-slave`. Team members cannot create, edit or delete VMs.

| Role | Scope | Purpose |
|---|---|---|
| `roles/iap.tunnelResourceAccessor` | project | open the IAP tunnel |
| `roles/compute.osAdminLogin` (`osLogin` when `can_sudo = false`) | project | OS Login on the VMs, with or without sudo |
| `roles/compute.viewer` | project | look up instances by name and zone, wait for operations |
| `roles/iam.serviceAccountUser` | the three VM service accounts (`demo3-nginx-sa`, `demo3-app-sa`, `demo3-db-sa`) | OS Login to a VM that runs as a service account |
| custom role `demo3VmPower` (`compute.instances.start`, `compute.instances.stop`), with a condition | project | power on and off |

All bindings are additive (`_member`), so existing grants on these roles are not changed. The power binding carries an IAM condition that limits it to instances named `demo3-*` in the zones listed in `vm_zones`; other VMs in the project are not affected. IAM conditions support `startsWith` but not `contains`, so the condition is one `startsWith` clause per zone, joined with `||`.

## Deploy service account

`demo3-deploy-sa` is the identity the runner uses to open SSH sessions to the VMs over the VPN. The runner holds only an SSH private key and no GCP credentials.

| Role | Scope |
|---|---|
| `roles/compute.osLogin` (`osAdminLogin` when `deploy_can_sudo = true`) | project |
| `roles/iam.serviceAccountUser` | the three VM service accounts |

No service account key is created. The runner's public key is added once to the account's OS Login profile, using impersonation (the administrator needs `roles/iam.serviceAccountTokenCreator` on the account). The commands are in the `deploy_key_commands` output. The runner then logs in with the account's OS Login user name:

```bash
ssh -i ~/.ssh/runner_deploy sa_116687368623049818165@10.20.1.2
```

The target is the VM's private IP. The account has no sudo unless `deploy_can_sudo` is set.

## Terraform service account

`demo3-terraform-sa` lets the runner run Terraform for the `application-gcp` root. No key exists for it. Authentication uses Workload Identity Federation:

1. The pool `demo3-aws` and its provider `aws-runner` accept only the assumed role `demo3-runner` in the AWS account `aws_account_id` (enforced by an attribute condition).
2. The principal set for that role has `roles/iam.workloadIdentityUser` on the service account.
3. On the runner, a credentials file (no secrets) tells Google client libraries to exchange the instance role's AWS credentials for short-lived service account tokens.

| Role | Purpose |
|---|---|
| `roles/compute.admin` | network, firewall, VMs, disks, addresses, Cloud NAT |
| `roles/iam.serviceAccountAdmin` | create the VM service accounts |
| `roles/iam.serviceAccountUser` | attach those service accounts to VMs |
| `roles/storage.admin` | create the application bucket, read and write the Terraform state bucket |
| `roles/resourcemanager.projectIamAdmin`, with a condition | grant roles to the VM service accounts. The condition (`modifiedGrantsByRole`) allows only `logging.logWriter` and `monitoring.metricWriter`, so the account cannot grant itself broader rights |

The root also enables `sts.googleapis.com`. The service account does not cover the `vpn`, `access-gcp` or `management-aws` roots.

The `runner_credential_config_command` output contains the command that creates the credentials file. The Docker executor cannot be used for jobs that need it, because the runner's instance metadata hop limit is 1 (see `management-aws`); the shell executor works.

## Variables

| Variable | Default | Meaning |
|---|---|---|
| `project_id` | none | GCP project ID |
| `team_emails` | `[]` | Google account emails of the team |
| `can_sudo` | `true` | `true` grants `osAdminLogin` (root on the VMs), `false` grants `osLogin` |
| `can_power_vms` | `true` | allow start and stop of the `demo3-*` VMs |
| `vm_zones` | `europe-west3-a`, `europe-west3-b` | zones where start and stop is allowed; add a zone when a VM is placed in a new one |
| `deploy_can_sudo` | `false` | grant the deploy account `osAdminLogin` |
| `aws_account_id` | none | AWS account of the runner; set in `terraform.tfvars`, which is not committed |
| `runner_aws_role` | `demo3-runner` | the only AWS role trusted for the Terraform service account |
| `name_prefix` | `demo3` | must match `application-gcp` |
| `vm_service_accounts` | `nginx`, `app`, `db` | VM service account roles created by `application-gcp` |
| `region`, `zone` | `europe-west3`, `europe-west3-a` | used only for the commands in the outputs |

## Outputs

`team_members`, `granted_project_roles`, `connect_command`, `power_commands`, `deploy_sa_email`, `deploy_key_commands`, `terraform_sa_email`, `runner_credential_config_command`.

## Notes

- To add or remove a team member, edit `team_emails` and apply this root only.
- Connecting also requires the `allow-iap-ssh` firewall rule created by `application-gcp`.
