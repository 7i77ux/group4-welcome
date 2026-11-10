#!/bin/sh
# Publish the welcome page on the Welcome + mail VM (10.4.255.11) and keep it always on.
# Put this file and index.md in the same folder (e.g. /home/user/Downloads), then as root:
#   sh /home/user/Downloads/deploy.sh
# Safe to run again: to update the page, download the new index.md and rerun.
set -e
SRC="$(dirname "$0")"

# 1. pandoc (Markdown -> HTML)
command -v pandoc >/dev/null || { apt-get update && apt-get install -y pandoc; }

# 2. page
mkdir -p /var/www/welcome
pandoc "$SRC/index.md" -s -o /var/www/welcome/index.html

# 3. nginx site (default site disabled; its file stays in sites-available)
cat > /etc/nginx/sites-available/welcome <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name welcome.group4.umons;
    root /var/www/welcome;
    index index.html;
    server_tokens off;
    location / {
        try_files $uri $uri/ =404;
    }
}
EOF
ln -sf /etc/nginx/sites-available/welcome /etc/nginx/sites-enabled/welcome
rm -f /etc/nginx/sites-enabled/default

# 4. always on: start at boot, restart 5 s after a crash
systemctl enable nginx
mkdir -p /etc/systemd/system/nginx.service.d
printf '[Service]\nRestart=on-failure\nRestartSec=5s\n' > /etc/systemd/system/nginx.service.d/restart.conf
systemctl daemon-reload

# 5. apply only if the configuration is valid
nginx -t
systemctl reload nginx

# 6. check
curl -s http://127.0.0.1/ | grep -o '<title>.*</title>'
echo "OK: http://welcome.group4.umons"
