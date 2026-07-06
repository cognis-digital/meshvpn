#!/usr/bin/env bash
# meshvpn - self-contained test suite (plain bash; no WireGuard, no network)
# Maintainer: Cognis Digital  |  License: COCL 1.0
#
# Exercises validate / lint / generate (mesh, hub, partial) / graph / export /
# keygen / healthcheck against the bundled examples plus deliberately broken
# fixtures generated in a temp dir. Exits non-zero if any assertion fails.

set -u

TESTS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -P "$TESTS_DIR/.." && pwd)"
MV="$ROOT/meshvpn.sh"
EXAMPLE="$ROOT/examples/fleet.conf"
DC="$ROOT/examples/datacenter.conf"

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  ok   - %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL - %s\n' "$1"; }

# result <ok?> <desc> : ok? is 0 for pass, non-zero for fail.
result() { if [ "$1" -eq 0 ]; then ok "$2"; else bad "$2"; fi; }

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
assert_pass "validate passes on datacenter example (optional fields)" \
    bash "$MV" validate --config "$DC"

JOUT="$(bash "$MV" validate --config "$EXAMPLE" --json 2>/dev/null)"
case "$JOUT" in *'"valid": true'*) ok "validate --json reports valid=true" ;; *) bad "validate --json missing valid=true" ;; esac

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
assert_fail "validate fails on duplicate node name" bash "$MV" validate --config "$DUP"

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
assert_fail "validate fails on overlay-IP collision" bash "$MV" validate --config "$COLL"

BADCIDR="$WORK/bad_cidr.conf"
cat > "$BADCIDR" <<'EOF'
[node]
name = alpha
endpoint = a.example.net:51820
overlay_ip = 10.66.0.300/33
allowed_ips = 10.66.0.1/32
EOF
assert_fail "validate fails on bad CIDR" bash "$MV" validate --config "$BADCIDR"

MISSING="$WORK/missing.conf"
cat > "$MISSING" <<'EOF'
[node]
name = alpha
overlay_ip = 10.66.0.1/32
allowed_ips = 10.66.0.1/32
EOF
assert_fail "validate fails on missing endpoint" bash "$MV" validate --config "$MISSING"

BADPORT="$WORK/bad_port.conf"
cat > "$BADPORT" <<'EOF'
[node]
name = alpha
endpoint = a.example.net:99999
overlay_ip = 10.66.0.1/32
allowed_ips = 10.66.0.1/32
EOF
assert_fail "validate fails on out-of-range port" bash "$MV" validate --config "$BADPORT"

BADMTU="$WORK/bad_mtu.conf"
cat > "$BADMTU" <<'EOF'
[node]
name = alpha
endpoint = a.example.net:51820
overlay_ip = 10.66.0.1/32
allowed_ips = 10.66.0.1/32
mtu = 99999
EOF
assert_fail "validate fails on out-of-range mtu" bash "$MV" validate --config "$BADMTU"

BADDNS="$WORK/bad_dns.conf"
cat > "$BADDNS" <<'EOF'
[node]
name = alpha
endpoint = a.example.net:51820
overlay_ip = 10.66.0.1/32
allowed_ips = 10.66.0.1/32
dns = not-an-ip
EOF
assert_fail "validate fails on bad dns server" bash "$MV" validate --config "$BADDNS"

V6="$WORK/v6.conf"
cat > "$V6" <<'EOF'
[node]
name = a
endpoint = a.example.net:51820
overlay_ip = fd00::1/128
allowed_ips = fd00::1/128
[node]
name = b
endpoint = b.example.net:51820
overlay_ip = fd00::2/128
allowed_ips = fd00::2/128
EOF
assert_pass "validate accepts IPv6 overlay CIDRs" bash "$MV" validate --config "$V6"

echo
# -------------------------------------------------------------------------
echo "[lint]"
assert_pass "lint passes on clean example" bash "$MV" lint --config "$EXAMPLE"
WIDE="$WORK/wide.conf"
cat > "$WIDE" <<'EOF'
[node]
name = a
endpoint = a.example.net:51820
overlay_ip = 10.66.0.1/24
allowed_ips = 0.0.0.0/0
[node]
name = b
endpoint = b.example.net:51820
overlay_ip = 10.66.0.2/32
allowed_ips = 10.66.0.2/32
EOF
assert_fail "lint warns on wide overlay prefix / default-route exit" bash "$MV" lint --config "$WIDE"

echo
# -------------------------------------------------------------------------
echo "[generate mesh]"
MESH_OUT="$WORK/mesh"
assert_pass "generate mesh succeeds" \
    bash "$MV" generate --config "$EXAMPLE" --topology mesh --out "$MESH_OUT"

NODE_COUNT="$(grep -c '^\[node\]' "$EXAMPLE")"
EXPECT_PEERS=$((NODE_COUNT - 1))

GEN_COUNT="$(find "$MESH_OUT" -maxdepth 1 -name 'wg*.conf' | wc -l | tr -d ' ')"
result "$([ "$GEN_COUNT" -eq "$NODE_COUNT" ] && echo 0 || echo 1)" \
    "mesh emits one conf per node ($GEN_COUNT == $NODE_COUNT)"

mesh_peers_ok=0
for f in "$MESH_OUT"/wg*.conf; do
    p="$(grep -c '^\[Peer\]' "$f")"
    [ "$p" -ne "$EXPECT_PEERS" ] && mesh_peers_ok=1
done
result "$mesh_peers_ok" "each mesh conf has N-1 ($EXPECT_PEERS) [Peer] blocks"

mesh_iface_ok=0
for f in "$MESH_OUT"/wg*.conf; do
    n="$(grep -c '^\[Interface\]' "$f")"
    [ "$n" -eq 1 ] || mesh_iface_ok=1
done
result "$mesh_iface_ok" "each mesh conf has exactly one [Interface]"

mesh_ph_ok=0
for f in "$MESH_OUT"/wg*.conf; do
    grep -q 'PrivateKey = <FILL_FROM_SECRET' "$f" || mesh_ph_ok=1
done
result "$mesh_ph_ok" "every mesh conf uses a PrivateKey placeholder"

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

HUB_PEERS="$(grep -c '^\[Peer\]' "$HUB_OUT/wg0.conf")"
result "$([ "$HUB_PEERS" -eq "$EXPECT_PEERS" ] && echo 0 || echo 1)" \
    "hub (wg0) has N-1 ($EXPECT_PEERS) [Peer] blocks"

spoke_ok=0
for f in "$HUB_OUT"/wg*.conf; do
    [ "$(basename "$f")" = "wg0.conf" ] && continue
    p="$(grep -c '^\[Peer\]' "$f")"
    [ "$p" -ne 1 ] && spoke_ok=1
done
result "$spoke_ok" "each spoke has exactly one [Peer] (the hub)"

HUB_NAME="$(grep -m1 '^name' "$EXAMPLE" | sed 's/.*=//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
spoke_peer_ok=0
for f in "$HUB_OUT"/wg*.conf; do
    [ "$(basename "$f")" = "wg0.conf" ] && continue
    grep -q "^# peer: $HUB_NAME$" "$f" || spoke_peer_ok=1
done
result "$spoke_peer_ok" "each spoke peers with the hub '$HUB_NAME'"

echo
# -------------------------------------------------------------------------
echo "[generate partial]"
PART_OUT="$WORK/partial"
assert_pass "generate partial succeeds" \
    bash "$MV" generate --config "$DC" --topology partial --out "$PART_OUT"
result "$([ "$(grep -c '^\[Peer\]' "$PART_OUT/wg0.conf")" -eq 3 ] && echo 0 || echo 1)" \
    "partial hub (gw) has 3 peers"
result "$([ "$(grep -c '^\[Peer\]' "$PART_OUT/wg1.conf")" -eq 2 ] && echo 0 || echo 1)" \
    "partial us-a peers with hub + same-group us-b (2)"
result "$([ "$(grep -c '^\[Peer\]' "$PART_OUT/wg3.conf")" -eq 1 ] && echo 0 || echo 1)" \
    "partial eu-a peers with hub only (1)"
if grep -q '^DNS = 10.80.0.1' "$PART_OUT/wg1.conf"; then ok "DNS field emitted for us-a"; else bad "DNS not emitted"; fi
if grep -q '^MTU = 1420' "$PART_OUT/wg0.conf"; then ok "MTU field emitted for gw"; else bad "MTU not emitted"; fi
if grep -q '^PersistentKeepalive = 15' "$PART_OUT/wg0.conf"; then ok "per-node keepalive override applied"; else bad "keepalive override missing"; fi

echo
# -------------------------------------------------------------------------
echo "[graph / export / keygen]"
assert_pass "graph ascii succeeds" bash "$MV" graph --config "$EXAMPLE" --topology hub
assert_pass "graph dot succeeds" bash "$MV" graph --config "$EXAMPLE" --format dot
assert_pass "graph mermaid succeeds" bash "$MV" graph --config "$EXAMPLE" --format mermaid
assert_fail "graph rejects unknown format" bash "$MV" graph --config "$EXAMPLE" --format svg

DOT="$(bash "$MV" graph --config "$EXAMPLE" --topology mesh --format dot 2>/dev/null)"
case "$DOT" in *'graph meshvpn {'*) ok "dot output has a graph header" ;; *) bad "dot output malformed" ;; esac

EXPORT="$(bash "$MV" export --config "$EXAMPLE" 2>/dev/null)"
case "$EXPORT" in *'"node_count": 4'*) ok "export reports node_count" ;; *) bad "export missing node_count" ;; esac
case "$EXPORT" in *'"is_hub": true'*) ok "export marks the hub node" ;; *) bad "export missing is_hub" ;; esac

KG="$(bash "$MV" keygen --config "$EXAMPLE" 2>/dev/null)"
case "$KG" in *'wg genkey'*) ok "keygen emits the wg genkey workflow" ;; *) bad "keygen missing wg genkey" ;; esac
if printf '%s' "$KG" | grep -qE '[A-Za-z0-9+/]{43}='; then
    bad "keygen output contains a real base64 key"
else
    ok "keygen output contains no real key material"
fi

echo
# -------------------------------------------------------------------------
echo "[healthcheck]"
DRY="$(bash "$MV" healthcheck --config "$EXAMPLE" --dry-run 2>&1)"
DRY_RC=$?
result "$DRY_RC" "healthcheck --dry-run exits 0"

dry_ok=0
while IFS= read -r ep; do
    ep="$(printf '%s' "$ep" | sed 's/.*=//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$ep" ] && continue
    printf '%s' "$DRY" | grep -qF "$ep" || dry_ok=1
done < <(grep '^endpoint' "$EXAMPLE")
result "$dry_ok" "dry-run lists every configured endpoint"

if printf '%s' "$DRY" | grep -q '\[fail\]'; then
    bad "dry-run unexpectedly performed a live probe"
else
    ok "dry-run performed no live probe"
fi

HCJSON="$(bash "$MV" healthcheck --config "$EXAMPLE" --json 2>/dev/null)"
case "$HCJSON" in *'"targets"'*) ok "healthcheck --json emits targets" ;; *) bad "healthcheck --json missing targets" ;; esac

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
