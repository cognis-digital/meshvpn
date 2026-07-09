#!/usr/bin/env sh
# meshvpn — POSIX installer. Symlinks (or copies) meshvpn.sh onto your PATH as
# `meshvpn`. Pure shell; no build step. Usage: ./install.sh [--prefix DIR]
set -eu

PREFIX="${PREFIX:-$HOME/.local}"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2 ;;
        --prefix=*) PREFIX="${1#*=}"; shift ;;
        -h|--help) echo "usage: install.sh [--prefix DIR]  (default: \$HOME/.local)"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

HERE="$(cd "$(dirname "$0")" && pwd)"
BINDIR="$PREFIX/bin"
mkdir -p "$BINDIR"

# meshvpn.sh sources lib/ relative to its own real path. We install a tiny
# wrapper that execs the real script in place, which is portable across systems
# whether or not they support real symlinks (MSYS 'ln' silently copies).
printf '#!/bin/sh\nexec "%s" "$@"\n' "$HERE/meshvpn.sh" > "$BINDIR/meshvpn"
chmod +x "$BINDIR/meshvpn"
chmod +x "$HERE/meshvpn.sh"

echo "installed: $BINDIR/meshvpn (wrapper -> $HERE/meshvpn.sh)"
echo "ensure $BINDIR is on your PATH, then: meshvpn --help"
