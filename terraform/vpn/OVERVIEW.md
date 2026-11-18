# vpn

Terraform root that connects the AWS management VPC (`10.10.0.0/16`) and the GCP application VPC (`10.20.0.0/16`) with an HA VPN (IPsec) and dynamic routing (BGP).

State: S3 bucket `demo3-tfstate-mgmt-bucket`, key `demo3/vpn.tfstate`. The tunnel pre-shared keys are stored in this state, so the bucket must stay private.

## Role in the platform

The root creates only the connection. It reads the VPC IDs, route table and network of both sides from the remote state of `management-aws` and `application-gcp` (`data.tf`), so both must be applied first. The only change it makes inside the existing networks is one route propagation on the AWS private route table.

## How it works

```
AWS 10.10.0.0/16                                     GCP 10.20.0.0/16
 private route table                                  Cloud Router (ASN 65020)
   learns 10.20.x.x  <-- BGP --                         learns 10.10.0.0/16
        |                                                    |
 Virtual private gateway (ASN 64512)              HA VPN gateway (interface 0, 1)
   VPN connection 0 : tunnel 1, 2  <==IPsec==>  interface 0 (2 tunnels)
   VPN connection 1 : tunnel 1, 2  <==IPsec==>  interface 1 (2 tunnels)
```

1. **GCP gateway.** An HA VPN gateway has two interfaces, each with its own public IP. A dedicated Cloud Router, `demo3-vpn-router` (separate from the NAT router), holds the BGP sessions.
2. **AWS side.** One customer gateway is created per GCP interface IP, and one VPN connection per customer gateway. Each connection has two tunnels, giving four tunnels in total. AWS generates the pre-shared keys and the tunnel endpoint IPs.
3. **GCP tunnels.** The four AWS endpoints are registered as one external gateway with `FOUR_IPS_REDUNDANCY`. Each GCP interface carries two tunnels, to the two endpoints of its own AWS connection.
4. **BGP.** Every tunnel has its own `/30` link-local range (`169.254.10.0/30` to `169.254.13.0/30`; AWS takes the first address, GCP the second). AWS advertises `10.10.0.0/16`; GCP advertises its two subnets, `10.20.0.0/24` and `10.20.1.0/24`. ASNs: AWS 64512, GCP 65020.
5. **Routes.** Route propagation is enabled on the AWS private route table, so the GCP subnets appear there automatically. GCP receives `10.10.0.0/16` as dynamic routes. No static routes are used.

When a tunnel or a GCP interface fails, BGP withdraws its routes and traffic uses the remaining tunnels.

## Traffic through the VPN

The VPN provides routing only. Whether a connection is allowed is decided by the firewalls on each side.

| Direction | Rule | Configured in |
|---|---|---|
| AWS to GCP | TCP 22 and ICMP from `10.10.0.0/16` (runner deployments over SSH) | `application-gcp`, firewall module, variable `management_cidr` |
| GCP to AWS | TCP 4317 and 4318 (OpenTelemetry) from `10.20.0.0/16` to SigNoz | `management-aws`, sg module, `additional_otlp_cidrs` |

All other traffic between the networks is blocked.

## Structure

| Part | Content |
|---|---|
| root | `main.tf` wires the modules, `data.tf` reads the other two states, `outputs.tf` provides `check_commands` |
| `modules/gcp_gateway` | HA VPN gateway and Cloud Router. Outputs the two interface IPs as a fixed-length list so that the AWS resources have a known count at plan time |
| `modules/aws_vpn` | virtual private gateway, customer gateways, VPN connections, route propagation. Outputs the tunnel endpoints and shared secrets |
| `modules/gcp_tunnels` | external gateway, the four tunnels, router interfaces and BGP peers |

Variables: `project_id` (required), `aws_region`, `gcp_region`, `name_prefix`, `aws_bgp_asn` (64512), `gcp_bgp_asn` (65020). A `check` block warns when `gcp_region` differs from the region used by `application-gcp`.

## Verification

The `check_commands` output lists the commands for the following checks:

- The four GCP tunnels show `ESTABLISHED`.
- The Cloud Router shows four BGP peers `UP` and a learned route to `10.10.0.0/16`.
- The AWS VPN connections show four tunnels `UP`.
- A connection test across the VPN, for example SSH from the runner to a GCP VM, or `curl` from a GCP VM to SigNoz on port 4318 (which succeeds only while the SigNoz collector is running).

## Notes

- **Regional routing.** The GCP VPC uses regional routing, so learned AWS routes apply to VMs in the VPN's region (`europe-west3`). Global routing would be needed for VMs in other regions.
- **Cost.** Two AWS VPN connections (about $0.05 per hour each) plus the GCP tunnels bill while the root exists.
- **Destroy order.** Destroy this root before `management-aws` and `application-gcp`, since it depends on both.
