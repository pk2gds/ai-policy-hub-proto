# GDS AI Policy Hub Prototype

## Introduction

This is a simple prototype to show how an AI Policy hub on GOV.UK might look & feel.

Right now it's made by capturing static HTML snapshots of various pages on on GOV.UK. 

There's probably a smarter way to do this via the [GOV.UK Prototype Toolkit](https://prototype-kit.service.gov.uk/docs/) but it's good enough for now.


## local development

Serve the pages by running `python3 -m http.server` then navigate to `http://[::]:8000` or `http://localhost:8000`

You can also use the helper script by running `sh ./dev.sh` or make the script executable by running `chmod +x run.sh` the first time. Then you can simply run `./dev.sh`



//VPS setup:

#!/usr/bin/env bash
set -euo pipefail

# ===============================
# Basic System Prep
# ===============================

apt update && apt upgrade -y
apt install -y nginx ufw curl git software-properties-common

# ===============================
# Firewall
# ===============================

ufw default deny incoming
ufw default allow outgoing
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# ===============================
# Install SSLH (Port Multiplexer)
# Allows SSH & HTTPS on port 443
# ===============================

apt install -y sslh

# Configure SSLH to listen on 443 and detect protocols
cat >/etc/default/sslh <<EOF
RUN=yes
DAEMON=/usr/sbin/sslh
DAEMON_OPTS="--user sslh \
--listen 0.0.0.0:443 \
--ssh 127.0.0.1:22 \
--tls 127.0.0.1:8443 \
--pidfile /var/run/sslh/sslh.pid"
EOF

# ===============================
# Nginx Reconfiguration
# ===============================

# Move Nginx HTTPS listener from 443 → 8443
sed -i 's/listen 443 ssl;/listen 8443 ssl;/g' /etc/nginx/sites-available/default || true

# Ensure a simple static root exists
mkdir -p /var/www/html
cat >/var/www/html/index.html <<EOF
<html><body><h1>VPS is Running Securely</h1></body></html>
EOF

# ===============================
# SSL – Let's Encrypt
# ===============================

apt install -y certbot python3-certbot-nginx
# Note: initial certificate must go via port 80 challenge

echo ">>> Please enter your domain name (DNS must already point here):"
read DOMAIN

certbot certonly --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@"$DOMAIN"

# After cert creation, ensure Nginx uses it under port 8443
sed -i "s|ssl_certificate .*|ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;|" /etc/nginx/sites-available/default
sed -i "s|ssl_certificate_key .*|ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;|" /etc/nginx/sites-available/default

# ===============================
# Strong Security Headers
# ===============================

cat >>/etc/nginx/snippets/security-headers.conf <<'EOF'
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header Referrer-Policy no-referrer-when-downgrade;
add_header X-XSS-Protection "1; mode=block";
add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload" always;
EOF

sed -i '/server_name _;/a \    include snippets/security-headers.conf;' /etc/nginx/sites-available/default

# ===============================
# Restart services
# ===============================
systemctl restart nginx
systemctl restart sslh

echo "=============================="
echo "Setup complete."
echo "HTTPS site available at: https://$DOMAIN"
echo "SSH available on port 443 through sslh."
echo "=============================="