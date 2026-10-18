#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

VERBOSE=0
CHECK_LINKS=1
BASE_URL="http://localhost:8081"

for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=1 ;;
    --no-check)   CHECK_LINKS=0 ;;
    http*)        BASE_URL="$arg" ;;
  esac
done

echo "[ ] building ..."
rm -rf output/

if [ "$VERBOSE" = "1" ]; then
  nix-shell shell.nix --run \
    "cd vokobe2 && dune exec bin/main.exe -- ../input/ ../output/ emile.space"
else
  nix-shell shell.nix --run \
    "cd vokobe2 && dune exec bin/main.exe -- ../input/ ../output/ emile.space" 2>/dev/null
fi

chmod -R +r output/
echo "[+] done"

if [ "$CHECK_LINKS" = "1" ]; then
  echo "[ ] checking links ($BASE_URL) ..."
  if [ "$VERBOSE" = "1" ]; then
    python3 check-links.py --verbose "$BASE_URL" || true
  else
    python3 check-links.py "$BASE_URL" || true
  fi
fi

echo "[ ] checking for links to hidden pages ..."
hidden_found=0
while IFS= read -r hidden_html; do
  page=$(basename "$hidden_html" .html)
  # search all HTML files (except the hidden page itself) for hrefs pointing to it
  matches=$(grep -rl "href=['\"]/${page}['\"]" output/ --include="*.html" 2>/dev/null \
            | grep -v "^output/${page}.html$" || true)
  if [ -n "$matches" ]; then
    echo "[!] WARNING: hidden page '${page}' is linked from:"
    echo "$matches" | sed 's/^/      /'
    hidden_found=1
  fi
done < <(find output/ -maxdepth 1 -name '.*html' 2>/dev/null)
if [ "$hidden_found" = "0" ]; then
  echo "[+] no links to hidden pages found"
fi
