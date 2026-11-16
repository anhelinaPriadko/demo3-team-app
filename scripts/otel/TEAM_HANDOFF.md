# Demo 3 — OpenTelemetry: requests to infrastructure/application owners

OpenTelemetry scripts and Collector configs are prepared for all six GCP VMs. To execute them end-to-end, please confirm or complete the following:

- [ ] SigNoz is deployed and OTLP/gRPC is listening on `10.10.0.118:4317`.
- [ ] VPN/BGP and the SigNoz security group allow TCP 4317 from `10.20.0.0/16`.
- [ ] Deployment identity can install packages, write `/etc/otelcol-contrib`, and restart systemd (current `deploy_can_sudo` default is `false`), or an admin will run the scripts.
- [ ] GitLab Runner setup is complete and a deployment job exists; the current pipeline only runs Terraform validate/plan/apply.
- [ ] Terraform output provides the dynamic private IP of `demo3-db-witness`.
- [ ] PostgreSQL logging path and `otelcol-contrib` read permissions are confirmed on master and replica.
- [ ] Application owner pins an OpenTelemetry Java Agent version, applies the Dockerfile/environment patch, and redeploys both Java app VMs.
- [ ] Team decides whether Nginx internal metrics, PostgreSQL/Patroni metrics and etcd metrics are required, and provides their endpoints/exporters and ports.
- [ ] Team confirms whether plaintext OTLP inside the VPN is acceptable or TLS/authentication is required.

## Commands once the witness IP and access are ready

```bash
# Nginx
sudo ./scripts/install.sh
sudo ./scripts/configure.sh nginx demo3-nginx 10.20.0.2
sudo ./scripts/verify.sh

# App 1 / App 2
sudo ./scripts/install.sh
sudo ./scripts/configure.sh app demo3-app-1 10.20.1.2
sudo ./scripts/configure.sh app demo3-app-2 10.20.1.5

# Database nodes
sudo ./scripts/install.sh
sudo ./scripts/configure.sh db-master demo3-db-master 10.20.1.4
sudo ./scripts/configure.sh db-slave demo3-db-slave 10.20.1.3

# Witness — replace with the actual Terraform output
sudo ./scripts/install.sh
sudo ./scripts/configure.sh witness demo3-db-witness <WITNESS_PRIVATE_IP>
```
