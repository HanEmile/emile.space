#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=1 ;;
  esac
done

BUILD_ARGS="$*"
SYNC_ARGS=""
if [ "$VERBOSE" = "1" ]; then
  SYNC_ARGS="--verbose"
fi

# data prep: one nix-shell for everything (dates, geodata, map regions).
# each step is internally stamped and exits in ~0 s when nothing changed.
nix-shell shell.nix --run '
set -e
echo "[ ] updating modified dates ..."
python3 update-modified.py
echo "[ ] updating map geodata ..."
python3 update-map-geodata.py
if [ -d map-cache/osm ]; then
  if python3 map-attrs-changed.py; then
    echo "[.] map regions unchanged"
  else
    echo "[ ] extracting missing map regions from local OSM dataset ..."
    (cd vokobe2 && dune exec bin/main.exe -- ../input/ ../output/ emile.space --dump-missing-queries >/dev/null)
    if ls map-cache/*.query >/dev/null 2>&1; then
      python3 extract-map-cache.py
    fi
    # repack the committed rich layer from the local region extracts
    python3 build-world-rich.py
  fi
fi
'

./build.sh $BUILD_ARGS
./sync.sh $SYNC_ARGS
