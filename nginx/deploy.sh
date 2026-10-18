#!/usr/bin/env bash
# Deploy nginx config to naraj and reload nginx.
# Run from v2/: ./nginx/deploy.sh
set -e

HOST=root@naraj
REMOTE_CONF=/etc/nginx/sites-available/emile.space
REMOTE_ENABLED=/etc/nginx/sites-enabled/emile.space

echo "[ ] uploading nginx config ..."
scp "$(dirname "$0")/emile.space.conf" "$HOST:$REMOTE_CONF"

echo "[ ] enabling site and reloading nginx ..."
ssh "$HOST" bash -s <<'EOF'
set -e
ln -sf /etc/nginx/sites-available/emile.space /etc/nginx/sites-enabled/emile.space
nginx -t
systemctl reload nginx
EOF

echo "[+] done"
