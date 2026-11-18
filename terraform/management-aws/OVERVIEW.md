# management-aws

Terraform root for the management environment on AWS: a VPC with GitLab, SigNoz and a GitLab runner. Region `eu-central-1`, availability zone `eu-central-1a`. All resources are prefixed `demo3-`.

State: S3 bucket `demo3-tfstate-mgmt-bucket`, key `demo3/terraform.tfstate` (encrypted, lockfile locking). Provider `hashicorp/aws ~> 6.0`.

## Role in the platform

This root is applied first. The `vpn` root reads its outputs (VPC ID, CIDR and private route table) to attach the VPN gateway and to receive the routes learned from GCP.

## Structure

`main.tf` wires four modules. The `ec2` module is called once per instance.

| Module | Creates |
|---|---|
| `network` | VPC, public and private subnet, Internet Gateway, NAT Gateway with an Elastic IP, route tables |
| `sg` | one security group each for GitLab, the runner and SigNoz, with their ingress and egress rules |
| `iam` | one role and instance profile per instance, with a Session Manager policy |
| `ec2` | one instance with its root volume, an optional separately managed data volume and attachment, IMDSv2 enforced |

`scripts/mount-data-volume.sh.tftpl` is the user-data template that mounts the data volume at `/data` and bind-mounts application directories from it.

## Network

| Resource | Value |
|---|---|
| VPC | `demo3-vpc`, `10.10.0.0/16`, DNS support and hostnames on |
| Private subnet | `10.10.0.0/24` (all instances) |
| Public subnet | `10.10.1.0/24` (NAT Gateway only) |
| Internet | Internet Gateway for the public subnet, NAT Gateway with an Elastic IP for the private subnet |
| Route tables | public: `0.0.0.0/0` to the Internet Gateway. private: `0.0.0.0/0` to the NAT Gateway |

Through the `vpn` root, the private route table also receives the GCP subnets (`10.20.0.0/24`, `10.20.1.0/24`) by route propagation.

## Compute

All instances run Ubuntu 24.04 LTS (latest Canonical AMI at first apply; a newer AMI does not replace a running instance), have no public IP and use encrypted `gp3` volumes with IMDSv2 only. Root volumes are 15 GiB. Access is through Session Manager; there is no SSH from the internet.

| Instance | Type | Private IP | Data volume | Mounted at |
|---|---|---|---|---|
| `demo3-gitlab` | m7i-flex.large | `10.10.0.224` | 10 GiB | `/data`, with bind mounts for `/etc/gitlab` and `/var/opt/gitlab` |
| `demo3-signoz` | c7i-flex.large | `10.10.0.118` | 10 GiB | `/data`, with a bind mount for `/var/lib/docker/volumes` |
| `demo3-runner` | t3.small | `10.10.0.223` | none | none |

Data volumes are separate resources and survive instance replacement; the user-data script formats a volume only when it is blank. Private addresses are assigned by AWS, kept across stop and start, but not reserved. The runner's instance metadata hop limit is 1, so processes in containers cannot read the instance role credentials.

## Allowed traffic

Security groups. Egress is open on all three groups, with a note in the code to narrow it later.

| Group | Ingress |
|---|---|
| `demo3-gitlab-sg` | TCP 443 and 80 from the runner group |
| `demo3-runner-sg` | none (the runner polls GitLab) |
| `demo3-signoz-sg` | TCP 4317 (OTLP gRPC) and 4318 (OTLP HTTP) from `10.10.0.0/16` and from `additional_otlp_cidrs` (`10.20.0.0/16`, the GCP network, over the VPN). TCP 8080 (web UI) from `10.10.0.0/16` |

Inbound traffic from the GCP network is limited to the two OTLP ports. The security groups do not allow ICMP, so ping from GCP to AWS fails even when the VPN works.

## IAM

One role and instance profile per instance (`demo3-gitlab`, `demo3-runner`, `demo3-signoz`), assumable by EC2 only.

| Role | Access |
|---|---|
| all three | custom Session Manager policy, used instead of `AmazonSSMManagedInstanceCore` |
| `demo3-gitlab` | also `ssm:GetParameter` on `/demo3/gitlab-sync/*` (repository sync secrets), and `kms:Decrypt` when a customer managed key is configured |

The `demo3-runner` role is also the identity trusted by the GCP Workload Identity pool in `access-gcp`.

## Outputs

`instance_ids`, `private_ips`, `ssm_commands` (ready-to-use Session Manager commands), `nat_public_ip` (for allowlists on external services), and for the `vpn` root: `vpc_id`, `vpc_cidr`, `private_route_table_id`.

Connect to an instance with:

```bash
aws ssm start-session --target <instance-id> --region eu-central-1
```

## Notes

- The NAT Gateway is the largest fixed cost of this root.
- `terraform destroy` removes the instances and, with them, the data volumes.
