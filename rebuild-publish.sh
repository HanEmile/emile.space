#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

echo "rebuilding vokobe2 and then publishing emile.space"
nix-shell shell.nix --run "cd vokobe2 && dune build"
./build.sh
./sync.sh
