#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

VERBOSE="${VERBOSE:-0}"
CHECK_LINKS=1
OFFLINE=0

for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=1 ;;
    --no-check)   CHECK_LINKS=0 ;;
    --offline)    OFFLINE=1 ;;
    http*)        : ;;  # base-URL no longer needed (checker stats output/)
  esac
done

OFFLINE_ARG=""
if [ "$OFFLINE" = "1" ]; then
  OFFLINE_ARG="--offline"
fi

echo "[ ] building ..."
rm -rf output/

# build once, then invoke the binary directly: skips dune exec's
# rebuild-check and process wrapper on every run (exit codes and
# stdout/stderr are forwarded identical to dune exec)
GEN="cd vokobe2 && dune build bin/main.exe && ./_build/default/bin/main.exe ../input/ ../output/ emile.space $OFFLINE_ARG"
if [ "$VERBOSE" = "1" ]; then
  ./nixrun.sh "$GEN"
else
  ./nixrun.sh "$GEN" 2>/dev/null
fi

chmod -R +r output/
echo "[+] done"

if [ "$CHECK_LINKS" = "1" ]; then
  echo "[ ] checking links ..."
  if [ "$VERBOSE" = "1" ]; then
    python3 tools/check-links.py --verbose || true
  else
    python3 tools/check-links.py || true
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
