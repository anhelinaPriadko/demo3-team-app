#!/usr/bin/env bash

set -euo pipefail

DOMAIN="cinema-service-team1.pp.ua"
EMAIL="devops.internship.softserve@gmail.com"
APP_SERVERS=("10.20.1.2" "10.20.1.5")
APP_PORT="8080"
CLIENT_MAX_BODY_SIZE="10m"

# Staging enabled. Switch to 0 to create a production certificate
CERTBOT_STAGING="${CERTBOT_STAGING:-1}"

CONF_FILE="/etc/nginx/conf.d/app.conf"

log()  { echo -e "\n\033[1;32m==> $*\033[0m"; }
warn() { echo -e "\033[1;33mWARNING: $*\033[0m"; }
die()  { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

# ---------- sudo check ----------
[[ $EUID -eq 0 ]]    || die "Run as root: sudo bash $0"

CERTBOT_DOMAINS=()

SERVER_NAMES="$DOMAIN www.$DOMAIN"
CERTBOT_DOMAINS=(-d "$DOMAIN" -d "www.$DOMAIN")

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

APT=(apt-get -o DPkg::Lock::Timeout=600)

# ---------- 0. Wait for first boot ----------
if command -v cloud-init >/dev/null; then
    log "Waiting for cloud-init to finish"
    cloud-init status --wait >/dev/null || warn "cloud-init reported an error, continuing"
fi

# ---------- 1. Update & upgrade ----------
log "Updating and upgrading packages"
"${APT[@]}" update
"${APT[@]}" -y upgrade

# ---------- 2. Install NGINX ----------
log "Installing NGINX"
"${APT[@]}" -y install nginx
systemctl enable --now nginx

# ---------- 3. Remove default site ----------
log "Removing default site"
rm -f /etc/nginx/sites-enabled/default

# ---------- 4. Create app.conf ----------
log "Writing $CONF_FILE"

cat > "$CONF_FILE" <<EOF
server_tokens off;

upstream java_app {
    least_conn;
    server ${APP_SERVERS[0]}:${APP_PORT} max_fails=3 fail_timeout=15s;
    server ${APP_SERVERS[1]}:${APP_PORT} max_fails=3 fail_timeout=15s;
    keepalive 16;
}

server {
    listen 80 default_server;
    server_name ${SERVER_NAMES};

    client_max_body_size ${CLIENT_MAX_BODY_SIZE};

    location / {
        proxy_pass http://java_app;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_connect_timeout 3s;
        proxy_read_timeout 60s;
        proxy_next_upstream error timeout http_502 http_503;
    }
}
EOF

nginx -t
systemctl reload nginx

# ---------- 5. Install Certbot ----------
log "Installing Certbot"
"${APT[@]}" -y install certbot python3-certbot-nginx

# ---------- 6. Get certificate & enable HTTPS ----------
CERTBOT_EXTRA=()
RENEWAL_CONF="/etc/letsencrypt/renewal/${DOMAIN}.conf"
if [[ "$CERTBOT_STAGING" == "1" ]]; then
    warn "Using Let's Encrypt STAGING: browsers will not trust this certificate"
    CERTBOT_EXTRA=(--staging --break-my-certs)
elif [[ -f "$RENEWAL_CONF" ]] && grep -q "acme-staging" "$RENEWAL_CONF"; then
    log "Replacing the staging certificate with a production one"
    CERTBOT_EXTRA=(--force-renewal)
fi

log "Requesting certificate for: $SERVER_NAMES"
certbot --nginx \
    "${CERTBOT_DOMAINS[@]}" \
    "${CERTBOT_EXTRA[@]}" \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    --redirect \
    --keep-until-expiring

nginx -t
systemctl reload nginx

# ---------- 7. Verify auto-renewal ----------
log "Testing certificate auto-renewal"
certbot renew --dry-run

log "Done! Test with:"
echo "  curl -I http://${DOMAIN}    # expect 301 -> https"
echo "  curl -I https://${DOMAIN}   # expect 200 from the app"