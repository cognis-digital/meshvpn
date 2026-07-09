#!/usr/bin/env bash
# meshvpn — runnable demo. Exercises every subcommand against the bundled
# examples. No WireGuard, no network, no key material. Exits 0 on success.
set -u
ROOT="$(cd -P "$(dirname "$0")/.." && pwd)"
MV="$ROOT/meshvpn.sh"
FLEET="$ROOT/examples/fleet.conf"
DC="$ROOT/examples/datacenter.conf"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

step() { echo; echo "== $* =="; }

step "1. validate the 4-node example (human + JSON)"
bash "$MV" validate --config "$FLEET" || exit 1
bash "$MV" validate --config "$FLEET" --json || exit 1

step "2. lint for best-practice advisories"
bash "$MV" lint --config "$FLEET"

step "3. render the mesh topology (ascii)"
bash "$MV" graph --config "$FLEET" --topology mesh

step "4. render the hub topology as Mermaid (paste into a GitHub comment)"
bash "$MV" graph --config "$FLEET" --topology hub --format mermaid

step "5. generate mesh configs (placeholder keys only)"
bash "$MV" generate --config "$FLEET" --topology mesh --out "$OUT/mesh" || exit 1
echo "-- berlin (wg0.conf) --"
sed -n '1,20p' "$OUT/mesh/wg0.conf"

step "6. partial topology: hub + intra-region mesh"
bash "$MV" graph --config "$DC" --topology partial
bash "$MV" generate --config "$DC" --topology partial --out "$OUT/partial" || exit 1

step "7. export the parsed fleet as JSON"
bash "$MV" export --config "$FLEET" | head -14

step "8. emit the out-of-band key-minting helper (meshvpn never runs it)"
bash "$MV" keygen --config "$FLEET" | sed -n '1,16p'

step "9. healthcheck --dry-run (no network)"
bash "$MV" healthcheck --config "$FLEET" --dry-run || exit 1

step "10. prove no real private keys were ever written"
if grep -RhE '^PrivateKey = [A-Za-z0-9+/]{43}=' "$OUT" >/dev/null 2>&1; then
    echo "FAIL: real key found"; exit 1
else
    echo "OK: all generated PrivateKey values are placeholders"
fi

echo; echo "demo OK"
