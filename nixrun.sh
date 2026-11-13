#!/usr/bin/env bash
# instant nix-shell: replay a cached shell.nix environment (~0.05 s)
# instead of paying the ~3 s nix evaluation on every invocation.
# Regenerates the cache via one real nix-shell call when shell.nix (or
# this script) is newer than the cache, or when the cached store paths
# were garbage-collected.
#
# usage: ./nixrun.sh '<command run from the repo root>'
set -e
cd "$(dirname "$0")"

CACHE=.nix-env-cache
STAMP=$CACHE/env

stale() {
  [ ! -f "$STAMP" ] && return 0
  [ shell.nix -nt "$STAMP" ] && return 0
  [ nixrun.sh -nt "$STAMP" ] && return 0
  # a nix gc may have killed the cached store paths: spot-check the first
  # PATH entry, fall back to regeneration when it vanished
  first_path=$(grep '^PATH=' "$STAMP" | head -1 | cut -d= -f2- | cut -d: -f1)
  [ ! -d "$first_path" ] && return 0
  return 1
}

if stale; then
  mkdir -p "$CACHE"
  # dump the post-shellHook environment (PATH, OCAMLPATH, opam vars, ...),
  # each value %q-escaped so sourcing is safe even for multi-line/weird
  # inherited session variables
  nix-shell shell.nix --run \
    'compgen -e | while read -r v; do printf "%s=%q\n" "$v" "${!v}"; done' \
    > "$CACHE/env.tmp"
  # drop volatile/session vars: TMPDIR points at the ephemeral per-shell
  # dir (gone after exit; dune chokes on it), the rest are meaningless
  grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$CACHE/env.tmp" \
    | grep -vE '^(TMPDIR|NIX_BUILD_TOP|PWD|OLDPWD|SHLVL|_)=' > "$STAMP"
  rm "$CACHE/env.tmp"
fi

env -i HOME="$HOME" TERM="${TERM:-xterm}" bash --noprofile --norc -c '
  set -a; . .nix-env-cache/env; set +a
  eval "$1"
' _ "$1"
