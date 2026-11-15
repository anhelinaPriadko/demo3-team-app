# access-gcp

Terraform root that controls who and what can access the GCP application project: the VM service accounts and their project roles, the team's access to the VMs, the identity the GitLab runner uses to deploy, and the identity it uses to run Terraform. It manages identities and access only and creates no infrastructure.

State: GCS bucket `demo3-tfstate-gcp`, prefix `demo3/access`.

## Role in the platform

This root is applied before `application-gcp`, which looks up the VM service accounts created here and attaches them to its VMs. It is run by a project administrator with their own credentials, not by the pipeline: the pipeline's service account cannot create service accounts or change project IAM. Destroying `application-gcp` leaves the service accounts and all access in place. Runner setup is described in [RUNNER_SETUP.md](RUNNER_SETUP.md).

## VM service accounts

One service account per VM role, so no VM uses the default Compute Engine account: `demo3-nginx-sa`, `demo3-app-sa`, `demo3-db-sa`, `demo3-etcd-sa`. `application-gcp` attaches them to the VMs and grants the bucket permissions.

The accounts hold no project roles. Logs and metrics go to SigNoz over OpenTelemetry (through the VPN), which needs no GCP permission. Basic VM metrics (CPU, disk, network) still appear in the console, because Google collects them from the host.

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
| `roles/iam.serviceAccountUser` | the VM service accounts (`demo3-nginx-sa`, `demo3-app-sa`, `demo3-db-sa`, `demo3-etcd-sa`) | OS Login to a VM that runs as a service account |
| custom role `demo3VmPower` (`compute.instances.start`, `compute.instances.stop`), with a condition | project | power on and off |

All bindings are additive (`_member`), so existing grants on these roles are not changed. The power binding carries an IAM condition that limits it to instances named `demo3-*` in `vm_zone_primary` or `vm_zone_secondary` (one binding per zone); other VMs in the project are not affected.

## Deploy service account

`demo3-deploy-sa` is the identity the runner uses to open SSH sessions to the VMs over the VPN. The runner holds only an SSH private key and no GCP credentials.

| Role | Scope |
|---|---|
| `roles/compute.osLogin` (`osAdminLogin` when `deploy_can_sudo = true`) | project |
| `roles/iam.serviceAccountUser` | the VM service accounts |

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

| Role | Scope | Purpose |
|---|---|---|
| `roles/compute.admin` | project | network, firewall, VMs, disks, addresses, Cloud NAT |
| `roles/storage.admin` | project | create the application bucket and its IAM bindings, read and write the Terraform state bucket |
| `roles/iam.serviceAccountUser` | the VM service accounts only | read those accounts and attach them to VMs |

The account cannot create service accounts or change project IAM, and it cannot attach any other service account in the project to a VM.

The root also enables `sts.googleapis.com`. The service account does not cover the `vpn`, `access-gcp` or `management-aws` roots.

The `runner_credential_config_command` output contains the command that creates the credentials file. The Docker executor cannot be used for jobs that need it, because the runner's instance metadata hop limit is 1 (see `management-aws`); the shell executor works.

## Variables

| Variable | Default | Meaning |
|---|---|---|
| `project_id` | none | GCP project ID |
| `team_emails` | `[]` | Google account emails of the team |
| `can_sudo` | `true` | `true` grants `osAdminLogin` (root on the VMs), `false` grants `osLogin` |
| `can_power_vms` | `true` | allow start and stop of the `demo3-*` VMs |
| `vm_zone_primary`, `vm_zone_secondary` | `europe-west3-a`, `europe-west3-b` | zones where start and stop is allowed |
| `deploy_can_sudo` | `false` | grant the deploy account `osAdminLogin` |
| `aws_account_id` | none | AWS account of the runner; set in `terraform.tfvars`, which is not committed |
| `runner_aws_role` | `demo3-runner` | the only AWS role trusted for the Terraform service account |
| `name_prefix` | `demo3` | prefix of the service account IDs, must match `application-gcp` |
| `region`, `zone` | `europe-west3`, `europe-west3-a` | used only for the commands in the outputs |

## Outputs

`vm_sa_emails`, `team_members`, `granted_project_roles`, `connect_command`, `power_commands`, `deploy_sa_email`, `deploy_key_commands`, `terraform_sa_email`, `runner_credential_config_command`.

## Notes

- To add or remove a team member, edit `team_emails` and apply this root only.
- Connecting also requires the `allow-iap-ssh` firewall rule created by `application-gcp`.
