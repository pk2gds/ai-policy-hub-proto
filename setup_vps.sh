#!/usr/bin/env bash
set -euo pipefail

# ===============================
# System Update
# ===============================
apt update && apt upgrade -y

# ===============================
# Remove Apache2 if installed
# ===============================
if dpkg -l | grep -q apache2; then
    echo ">>> Apache2 detected. Removing..."
    systemctl stop apache2 || true
    systemctl disable apache2 || true
    apt purge -y apache2 apache2-utils apache2-bin apache2.2-common || true
    apt autoremove -y
    echo ">>> Apache2 removed."
else
    echo ">>> Apache2 not installed."
fi

# ===============================
# Install Required Packages
# ===============================
apt install -y nginx ufw curl git software-properties-common sslh

# ===============================
# Firewall Configuration
# ===============================
ufw default deny incoming
ufw default allow outgoing
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# ===============================
# Configure SSLH
# Multiplex SSH + HTTPS on 443
# ===============================
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
# Initial Nginx Config (NO SSL YET)
# This must succeed BEFORE certbot runs.
# ===============================

mkdir -p /etc/nginx/snippets

cat >/etc/nginx/snippets/security-headers.conf <<'EOF'
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header Referrer-Policy no-referrer-when-downgrade;
add_header X-XSS-Protection "1; mode=block";
add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload" always;
EOF

cat >/etc/nginx/sites-available/default <<'EOF'
# Redirect all HTTP → HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name _;
    return 301 https://$host$request_uri;
}

# Placeholder HTTPS server (8443, no SSL yet!)
server {
    listen 8443;
    listen [::]:8443;

    root /var/www/html;
    index index.html index.htm;
    server_name _;

    include snippets/security-headers.conf;
}
EOF

# Create simple site content
mkdir -p /var/www/html
echo "<h1>Secure VPS Setup (Pre-SSL)</h1>" >/var/www/html/index.html

# Restart nginx with non-SSL config
systemctl restart nginx

# ===============================
# Certificates – Let’s Encrypt
# ===============================
apt install -y certbot python3-certbot-nginx

echo ">>> Enter your domain name:"
read DOMAIN

echo ">>> Obtaining certificates for $DOMAIN ..."
certbot certonly --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@"$DOMAIN"

# ===============================
# Inject SSL Configuration AFTER Cert Exists
# ===============================
echo ">>> Adding SSL configuration to nginx..."

sed -i "/listen 8443;/a \
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;\n\
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;\n\
    ssl_protocols TLSv1.2 TLSv1.3;\n\
    ssl_prefer_server_ciphers on;" \
    /etc/nginx/sites-available/default

# Restart nginx with SSL enabled
systemctl restart nginx
systemctl restart sslh

echo "======================================================"
echo "SETUP COMPLETE!"
echo "Website: https://$DOMAIN"
echo "HTTP → HTTPS redirect: ENABLED"
echo "Internal nginx SSL port: 8443"
echo "Public HTTPS port: 443 (via sslh)"
echo "SSH reachable on port 443 (multiplexed)"
echo "======================================================"