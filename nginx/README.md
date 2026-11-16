# Nginx setup

`nginx-setup.sh` installs Nginx on `demo3-nginx`, proxies to the two app servers (`10.20.1.2`, `10.20.1.5`, port 8080) and enables HTTPS with a Let's Encrypt certificate for `cinema-service-team1.pp.ua` and `www.`. Safe to rerun.

## Running it from the pipeline

The runner connects over the VPN as the OS Login user of `demo3-deploy-sa`, which has sudo on the VMs.

```bash
SSH_USER="sa_116687368623049818165"
SSH_OPTS="-i /home/gitlab-runner/.ssh/gcp_deploy -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR"
NGINX_IP=10.20.0.2

scp $SSH_OPTS nginx/nginx-setup.sh "$SSH_USER@$NGINX_IP:/tmp/nginx-setup.sh"
ssh $SSH_OPTS "$SSH_USER@$NGINX_IP" "sudo bash /tmp/nginx-setup.sh && rm -f /tmp/nginx-setup.sh"
```

- Use the **private** IP: SSH is open only from the AWS network (`10.10.0.0/16`), not from the internet.
- The script must run as root (`sudo`), otherwise it exits.
- On a fresh VM the first minutes may be spent waiting for cloud-init and the apt lock. This is expected.

## Requirements

- `application-gcp` applied, and the domain's A records resolving to the Nginx public IP (needed for the certificate).
- The deploy key on the runner at `/home/gitlab-runner/.ssh/gcp_deploy` (mode `600`), and `jq` installed.

## Certificate: staging by default

`CERTBOT_STAGING` defaults to `1`: certificates come from Let's Encrypt **staging**, which browsers do not trust but which has no practical rate limit. Production allows only 5 certificates per week for the same names, and every rebuilt VM requests a new one.

For a trusted certificate (for example before the demo), pass `0`:

```bash
ssh $SSH_OPTS "$SSH_USER@$NGINX_IP" "sudo CERTBOT_STAGING=0 bash /tmp/nginx-setup.sh"
```

A staging certificate already on the VM is then replaced automatically. Set the variable after `sudo`, because `sudo` does not pass the environment through.
