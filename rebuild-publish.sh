#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

echo "rebuilding vokobe2, then publishing emile.space (skipping data prep)"
nix-shell shell.nix --run "cd vokobe2 && dune build"
./publish.sh --no-prep "$@"
