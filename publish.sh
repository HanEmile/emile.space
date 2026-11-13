#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

VERBOSE="${VERBOSE:-0}"
PREP=1
BUILD_ARGS=""
for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=1 ;;
    --no-prep)    PREP=0 ;;
    *)            BUILD_ARGS="$BUILD_ARGS $arg" ;;
  esac
done
export VERBOSE  # honored by build.sh and sync.sh

if [ "$PREP" = "1" ]; then
  # data prep: one cached-shell invocation for everything (dates, geodata,
  # map regions).  each step is internally stamped and exits in ~0 s when
  # nothing changed.
  ./nixrun.sh '
set -e
echo "[ ] updating modified dates ..."
python3 tools/update-modified.py
echo "[ ] updating map geodata ..."
python3 tools/update-map-geodata.py
if [ -d map-cache/osm ]; then
  if python3 tools/map-attrs-changed.py; then
    echo "[.] map regions unchanged"
  else
    echo "[ ] extracting missing map regions from local OSM dataset ..."
    (cd vokobe2 && dune build bin/main.exe && ./_build/default/bin/main.exe ../input/ ../output/ emile.space --dump-missing-queries >/dev/null)
    if ls map-cache/*.query >/dev/null 2>&1; then
      python3 tools/extract-map-cache.py
    fi
    # repack the committed rich layer from the local region extracts
    python3 tools/build-world-rich.py
  fi
fi
'
fi

# shellcheck disable=SC2086
./build.sh $BUILD_ARGS
./sync.sh
