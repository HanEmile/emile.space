#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

python3 tools/clean_url_server.py 8081 output/
