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
# Install Nginx + utilities
# ===============================
apt install -y nginx ufw curl git software-properties-common

# ===============================
# Firewall rules
# ===============================
ufw default deny incoming
ufw default allow outgoing
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# ===============================
# Install SSLH (Port Multiplexer)
# - Allows SSH + HTTPS on port 443
# ===============================
apt install -y sslh

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
# NGINX Configuration
# ===============================

# Build a complete default config: HTTP redirect + HTTPS server
cat >/etc/nginx/sites-available/default <<'EOF'
# Redirect HTTP → HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name _;
    return 301 https://$host$request_uri;
}

# Actual HTTPS server (nginx listens on 8443; sslh handles 443)
server {
    listen 8443 ssl;
    listen [::]:8443 ssl;

    root /var/www/html;
    index index.html index.htm;

    server_name _;

    include snippets/security-headers.conf;

    ssl_certificate /etc/letsencrypt/live/REPLACE_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/REPLACE_DOMAIN/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
}
EOF

# Create minimal index.html
mkdir -p /var/www/html
echo "<h1>Secure VPS with Nginx + SSL</h1>" >/var/www/html/index.html

# ===============================
# SSL – Let's Encrypt
# ===============================
apt install -y certbot python3-certbot-nginx

echo ">>> Enter your domain name:"
read DOMAIN

# Obtain cert using Nginx for HTTP challenge
certbot certonly --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@"$DOMAIN"

# Update placeholder paths in nginx config
sed -i "s|REPLACE_DOMAIN|$DOMAIN|g" /etc/nginx/sites-available/default

# ===============================
# Security Headers
# ===============================
mkdir -p /etc/nginx/snippets
cat >/etc/nginx/snippets/security-headers.conf <<'EOF'
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header Referrer-Policy no-referrer-when-downgrade;
add_header X-XSS-Protection "1; mode=block";
add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload" always;
EOF

# ===============================
# Restart services
# ===============================
systemctl restart nginx
systemctl restart sslh

echo "==============================================="
echo "Setup complete!"
echo "Site available at: https://$DOMAIN"
echo "HTTP correctly redirects to HTTPS."
echo "SSH available on port 443 (multiplexed via sslh)."
echo "==============================================="