#!/usr/bin/env bash
# meshvpn - self-contained test suite (plain bash; no WireGuard, no network)
# Maintainer: Cognis Digital  |  License: COCL 1.0
#
# Exercises validate / generate (mesh & hub) / healthcheck --dry-run against
# the bundled example plus a set of deliberately broken fixtures generated in
# a temp dir. Exits non-zero if any assertion fails.

set -u

TESTS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -P "$TESTS_DIR/.." && pwd)"
MV="$ROOT/meshvpn.sh"
EXAMPLE="$ROOT/examples/fleet.conf"

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  ok   - %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL - %s\n' "$1"; }

# assert_pass <desc> <cmd...> : command must exit 0.
assert_pass() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc (expected exit 0)"; fi
}
# assert_fail <desc> <cmd...> : command must exit non-zero.
assert_fail() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then bad "$desc (expected non-zero exit)"; else ok "$desc"; fi
}

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/meshvpn_test.$$")"
mkdir -p "$WORK"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

echo "meshvpn test suite"
echo "root: $ROOT"
echo

# -------------------------------------------------------------------------
echo "[validate]"
assert_pass "validate passes on bundled example" \
    bash "$MV" validate --config "$EXAMPLE"

# Fixture: duplicate node name.
DUP="$WORK/dup_name.conf"
cat > "$DUP" <<'EOF'
[node]
name = alpha
endpoint = a.example.net:51820
overlay_ip = 10.66.0.1/32
allowed_ips = 10.66.0.1/32
[node]
name = alpha
endpoint = b.example.net:51820
overlay_ip = 10.66.0.2/32
allowed_ips = 10.66.0.2/32
EOF
assert_fail "validate fails on duplicate node name" \
    bash "$MV" validate --config "$DUP"

# Fixture: overlay-IP collision (same address, any prefix).
COLL="$WORK/overlap_ip.conf"
cat > "$COLL" <<'EOF'
[node]
name = alpha
endpoint = a.example.net:51820
overlay_ip = 10.66.0.1/32
allowed_ips = 10.66.0.1/32
[node]
name = bravo
endpoint = b.example.net:51820
overlay_ip = 10.66.0.1/24
allowed_ips = 10.66.0.1/32
EOF
assert_fail "validate fails on overlay-IP collision" \
    bash "$MV" validate --config "$COLL"

# Fixture: bad CIDR.
BADCIDR="$WORK/bad_cidr.conf"
cat > "$BADCIDR" <<'EOF'
[node]
name = alpha
endpoint = a.example.net:51820
overlay_ip = 10.66.0.300/33
allowed_ips = 10.66.0.1/32
EOF
assert_fail "validate fails on bad CIDR" \
    bash "$MV" validate --config "$BADCIDR"

# Fixture: missing required field (no endpoint).
MISSING="$WORK/missing.conf"
cat > "$MISSING" <<'EOF'
[node]
name = alpha
overlay_ip = 10.66.0.1/32
allowed_ips = 10.66.0.1/32
EOF
assert_fail "validate fails on missing endpoint" \
    bash "$MV" validate --config "$MISSING"

# Fixture: bad port.
BADPORT="$WORK/bad_port.conf"
cat > "$BADPORT" <<'EOF'
[node]
name = alpha
endpoint = a.example.net:99999
overlay_ip = 10.66.0.1/32
allowed_ips = 10.66.0.1/32
EOF
assert_fail "validate fails on out-of-range port" \
    bash "$MV" validate --config "$BADPORT"

echo
# -------------------------------------------------------------------------
echo "[generate mesh]"
MESH_OUT="$WORK/mesh"
assert_pass "generate mesh succeeds" \
    bash "$MV" generate --config "$EXAMPLE" --topology mesh --out "$MESH_OUT"

# Count nodes in the example (number of [node] headers).
NODE_COUNT="$(grep -c '^\[node\]' "$EXAMPLE")"
EXPECT_PEERS=$((NODE_COUNT - 1))

# One conf per node.
GEN_COUNT="$(find "$MESH_OUT" -maxdepth 1 -name 'wg*.conf' | wc -l | tr -d ' ')"
if [ "$GEN_COUNT" -eq "$NODE_COUNT" ]; then
    ok "mesh emits one conf per node ($GEN_COUNT == $NODE_COUNT)"
else
    bad "mesh conf count $GEN_COUNT != node count $NODE_COUNT"
fi

# Each conf has N-1 [Peer] blocks.
mesh_peers_ok=1
for f in "$MESH_OUT"/wg*.conf; do
    p="$(grep -c '^\[Peer\]' "$f")"
    if [ "$p" -ne "$EXPECT_PEERS" ]; then
        mesh_peers_ok=0
        echo "    $f has $p peers, expected $EXPECT_PEERS"
    fi
done
if [ "$mesh_peers_ok" -eq 1 ]; then
    ok "each mesh conf has N-1 ($EXPECT_PEERS) [Peer] blocks"
else
    bad "some mesh conf has wrong [Peer] count"
fi

# Each conf has exactly one [Interface] block.
mesh_iface_ok=1
for f in "$MESH_OUT"/wg*.conf; do
    n="$(grep -c '^\[Interface\]' "$f")"
    [ "$n" -eq 1 ] || { mesh_iface_ok=0; echo "    $f has $n [Interface] blocks"; }
done
[ "$mesh_iface_ok" -eq 1 ] && ok "each mesh conf has exactly one [Interface]" \
    || bad "some mesh conf has wrong [Interface] count"

# Every conf has the private-key placeholder.
mesh_ph_ok=1
for f in "$MESH_OUT"/wg*.conf; do
    grep -q 'PrivateKey = <FILL_FROM_SECRET' "$f" || { mesh_ph_ok=0; echo "    $f missing placeholder"; }
done
[ "$mesh_ph_ok" -eq 1 ] && ok "every mesh conf uses a PrivateKey placeholder" \
    || bad "a mesh conf is missing the PrivateKey placeholder"

# No real private keys: WireGuard keys are 44-char base64 ending in '='.
# Assert no PrivateKey line carries such a literal.
if grep -RhE '^PrivateKey = [A-Za-z0-9+/]{43}=' "$MESH_OUT" >/dev/null 2>&1; then
    bad "mesh conf appears to contain a real base64 private key"
else
    ok "no real (base64) private keys present in mesh output"
fi

echo
# -------------------------------------------------------------------------
echo "[generate hub]"
HUB_OUT="$WORK/hub"
assert_pass "generate hub succeeds" \
    bash "$MV" generate --config "$EXAMPLE" --topology hub --out "$HUB_OUT"

# Hub is wg0 (first node). It should have N-1 peers.
HUB_PEERS="$(grep -c '^\[Peer\]' "$HUB_OUT/wg0.conf")"
if [ "$HUB_PEERS" -eq "$EXPECT_PEERS" ]; then
    ok "hub (wg0) has N-1 ($EXPECT_PEERS) [Peer] blocks"
else
    bad "hub has $HUB_PEERS peers, expected $EXPECT_PEERS"
fi

# Each spoke (wg1..) should have exactly 1 peer (the hub).
spoke_ok=1
for f in "$HUB_OUT"/wg*.conf; do
    base="$(basename "$f")"
    [ "$base" = "wg0.conf" ] && continue
    p="$(grep -c '^\[Peer\]' "$f")"
    if [ "$p" -ne 1 ]; then
        spoke_ok=0
        echo "    $f has $p peers, expected 1"
    fi
done
[ "$spoke_ok" -eq 1 ] && ok "each spoke has exactly one [Peer] (the hub)" \
    || bad "a spoke has the wrong [Peer] count"

# Spoke's single peer must be the hub node (berlin).
HUB_NAME="$(grep -m1 '^name' "$EXAMPLE" | sed 's/.*=//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
spoke_peer_ok=1
for f in "$HUB_OUT"/wg*.conf; do
    base="$(basename "$f")"
    [ "$base" = "wg0.conf" ] && continue
    grep -q "^# peer: $HUB_NAME$" "$f" || { spoke_peer_ok=0; echo "    $f peer is not $HUB_NAME"; }
done
[ "$spoke_peer_ok" -eq 1 ] && ok "each spoke peers with the hub '$HUB_NAME'" \
    || bad "a spoke peers with something other than the hub"

# No real private keys in hub output either.
if grep -RhE '^PrivateKey = [A-Za-z0-9+/]{43}=' "$HUB_OUT" >/dev/null 2>&1; then
    bad "hub conf appears to contain a real base64 private key"
else
    ok "no real (base64) private keys present in hub output"
fi

echo
# -------------------------------------------------------------------------
echo "[healthcheck --dry-run]"
DRY="$(bash "$MV" healthcheck --config "$EXAMPLE" --dry-run 2>&1)"
DRY_RC=$?
[ "$DRY_RC" -eq 0 ] && ok "healthcheck --dry-run exits 0" || bad "healthcheck --dry-run exit $DRY_RC"

# Every endpoint from the config must appear in the dry-run output.
dry_ok=1
while IFS= read -r ep; do
    ep="$(printf '%s' "$ep" | sed 's/.*=//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$ep" ] && continue
    printf '%s' "$DRY" | grep -qF "$ep" || { dry_ok=0; echo "    missing endpoint: $ep"; }
done < <(grep '^endpoint' "$EXAMPLE")
[ "$dry_ok" -eq 1 ] && ok "dry-run lists every configured endpoint" \
    || bad "dry-run missing one or more endpoints"

# Dry-run must NOT have printed any failure markers (proves no network probe).
if printf '%s' "$DRY" | grep -q '\[fail\]'; then
    bad "dry-run unexpectedly performed a live probe"
else
    ok "dry-run performed no live probe"
fi

echo
# -------------------------------------------------------------------------
echo "[cli basics]"
assert_pass "--help exits 0" bash "$MV" --help
assert_pass "--version exits 0" bash "$MV" --version
assert_fail "unknown command exits non-zero" bash "$MV" bogus
assert_fail "generate with bad topology exits non-zero" \
    bash "$MV" generate --config "$EXAMPLE" --topology ring --out "$WORK/ring"

echo
echo "================================"
echo "PASS: $PASS   FAIL: $FAIL"
echo "================================"
[ "$FAIL" -eq 0 ]
