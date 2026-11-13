#!/usr/bin/env bash
# Download Geofabrik country extracts and filter them down to the feature
# classes vokobe2's map renderer uses (same set as the Overpass query in
# vokobe2/lib/roughmap.ml: roads motorway..secondary, waterways, water
# bodies, reservoirs, coastlines).
#
# Raw extracts are deleted right after filtering: ~26 GB download turns
# into ~2-4 GB of kept data.  Filtered files live in map-cache/osm/ and
# let extract-map-cache.py rebuild every map-cache/<region>.json
# completely offline (also for future regions).
#
# Run inside nix:  nix-shell shell.nix --run './tools/tools/fetch-osm-dataset.sh'
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=map-cache/osm
mkdir -p "$OUT"

# single source of truth: mapconsts.EXTRACTS (used by
# extract-map-cache.py's country->extract mapping)
EXTRACTS="$(python3 tools/extract-map-cache.py --list-extracts)"

FILTER_EXPRS=(
  'w/highway=motorway,motorway_link,trunk,trunk_link,primary,primary_link,secondary'
  'w/waterway=river,canal,stream'
  'nwr/natural=water,coastline'
  'nwr/landuse=reservoir'
)

for path in $EXTRACTS; do
  name="$(basename "$path")"
  filtered="$OUT/$name.filtered.osm.pbf"
  if [ -f "$filtered.done" ]; then
    echo "[=] $name already filtered"
    continue
  fi
  raw="$OUT/$name-latest.raw.osm.pbf"
  url="https://download.geofabrik.de/$path-latest.osm.pbf"
  echo "[ ] downloading $name ..."
  curl -L --fail --retry 3 --retry-delay 10 -C - -o "$raw" "$url"
  echo "[ ] filtering $name ..."
  osmium tags-filter "$raw" "${FILTER_EXPRS[@]}" \
    -o "$filtered" --overwrite --no-progress
  rm -f "$raw"
  touch "$filtered.done"
  echo "[+] $name done ($(du -h "$filtered" | cut -f1))"
done
echo "[+] all extracts ready in $OUT"
du -sh "$OUT"
