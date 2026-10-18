#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=1 ;;
  esac
done

BUILD_ARGS=""
SYNC_ARGS=""
if [ "$VERBOSE" = "1" ]; then
  BUILD_ARGS="--verbose"
  SYNC_ARGS="--verbose"
fi

./build.sh $BUILD_ARGS
./sync.sh $SYNC_ARGS
