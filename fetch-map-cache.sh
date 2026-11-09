#!/usr/bin/env bash
# Fetch vokobe2 map cache regions in parallel.
#
# vokobe2 run with --dump-missing-queries writes one
# map-cache/<region>.query file per not-yet-cached Overpass region
# instead of fetching them sequentially.  This script downloads all of
# them in parallel (same endpoints, UA and cache naming as
# vokobe2/lib/roughmap.ml) and removes each .query file on success, so
# the next build finds everything cached.
#
# The default output of an Overpass query is compact JSON; the renderer
# accepts it as-is (it re-minifies when IT writes the cache itself).
#
# Can be copied to a fast host to do the downloads there:
#   rsync map-cache/*.query fetch-map-cache.sh medano:mapfetch/
#   ssh medano 'cd mapfetch && ./fetch-map-cache.sh . 8'
#   rsync 'medano:mapfetch/*.json' map-cache/
#
# usage: ./fetch-map-cache.sh [map-cache-dir] [workers]

set -u
DIR="${1:-map-cache}"
# Overpass allows ~2 concurrent queries per endpoint and IP; higher
# worker counts just produce 429s (they are retried, but politely slow)
WORKERS="${2:-4}"

# space-separated string: arrays can't be exported to the xargs subshells
ENDPOINTS="https://overpass-api.de/api/interpreter \
https://overpass.private.coffee/api/interpreter \
https://overpass.nchc.org.tw/api/interpreter \
https://overpass.openstreetmap.ru/api/interpreter"
UA="vokobe2 map renderer (https://emile.space)"

fetch_one() {
  local q="$1"
  # <region>.json.query -> <region>.json
  local out="${q%.query}"
  # already downloaded before (or fetched by a previous run): the json
  # is the cache, just drop the stale query file
  if [ -s "$out" ]; then
    rm -f "$q"
    echo "cached: $(basename "$out")"
    return 0
  fi
  local tmp="$out.tmp.$$.$RANDOM"
  local ENDPOINT_LIST=($ENDPOINTS)
  local n=${#ENDPOINT_LIST[@]}
  local start=$((RANDOM % n))
  local round i ep
  # Overpass gives ~2 concurrent query slots per endpoint and IP; beyond
  # that it answers 429.  Retry a few rounds with jittered backoff: the
  # slots free up as other queries finish.
  for round in 1 2 3 4 5 6; do
    for ((i = 0; i < n; i++)); do
      ep="${ENDPOINT_LIST[$(((start + i) % n))]}"
      if curl -sS --fail --connect-timeout 10 --max-time 120 -A "$UA" \
          -o "$tmp" --data-urlencode "data@$q" "$ep" \
         && [ -s "$tmp" ] && [ "$(head -c1 "$tmp")" = "{" ]; then
        mv "$tmp" "$out"
        rm -f "$q"
        echo "ok: $(basename "$out")"
        return 0
      fi
      rm -f "$tmp"
      sleep 2
    done
    sleep $((15 + RANDOM % 20))
  done
  echo "FAILED: $q"
  return 1
}
export -f fetch_one
export UA ENDPOINTS

shopt -s nullglob
queries=("$DIR"/*.query)
if [ ${#queries[@]} -eq 0 ]; then
  echo "nothing to fetch (no $DIR/*.query files)"
  exit 0
fi
echo "fetching ${#queries[@]} region(s) with $WORKERS workers ..."
printf '%s\n' "${queries[@]}" | xargs -P "$WORKERS" -I{} bash -c 'fetch_one "$1"' _ {}
