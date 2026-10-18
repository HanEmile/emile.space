#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=1 ;;
  esac
done

RSYNC_FLAGS="-a --checksum --links --delete --exclude '.git'"
if [ "$VERBOSE" = "1" ]; then
  RSYNC_FLAGS="-av --checksum --links --delete --exclude '.git'"
fi

echo "[ ] syncing ..."
# shellcheck disable=SC2086
time rsync $RSYNC_FLAGS output/ root@naraj:/var/www/emile.space/
ssh root@naraj chmod -R +r /var/www/emile.space/*
echo "[+] done syncing"
