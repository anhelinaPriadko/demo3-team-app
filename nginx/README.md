# Nginx setup

`nginx-setup.sh` installs Nginx on `demo3-nginx`, proxies to the app servers given in `APP_IPS` (port 8080) and enables HTTPS with a Let's Encrypt certificate for `cinema-service-team1.pp.ua` and `www.`. Safe to rerun.

## Running it from the pipeline

The runner connects over the VPN as the OS Login user of `demo3-deploy-sa`, which has sudo on the VMs.

```bash
SSH_USER="sa_116687368623049818165"
SSH_OPTS="-i /home/gitlab-runner/.ssh/gcp_deploy -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR"
# tf-outputs.json = `terraform output -json` of application-gcp, saved by the apply job
NGINX_IP=$(jq -r '.private_ips.value.nginx' tf-outputs.json)
APP_IPS=$(jq -r '.app_private_ips.value | join(" ")' tf-outputs.json)

scp $SSH_OPTS nginx/nginx-setup.sh "$SSH_USER@$NGINX_IP:/tmp/nginx-setup.sh"
ssh $SSH_OPTS "$SSH_USER@$NGINX_IP" "sudo APP_IPS='$APP_IPS' bash /tmp/nginx-setup.sh && rm -f /tmp/nginx-setup.sh"
```

- `APP_IPS` is required: the app IPs are assigned by GCP, so they always come from the `app_private_ips` output. The script stops if it is empty or contains something that is not an IPv4 address. Rerun the script after `app_count` changes, so Nginx gets the new list.
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
ssh $SSH_OPTS "$SSH_USER@$NGINX_IP" "sudo APP_IPS='$APP_IPS' CERTBOT_STAGING=0 bash /tmp/nginx-setup.sh"
```

A staging certificate already on the VM is then replaced automatically. Set the variable after `sudo`, because `sudo` does not pass the environment through.
