# shellcheck shell=bash
# meshvpn - advisory config linter
# Maintainer: Cognis Digital
# License: COCL 1.0
#
# `validate` answers "is this config well-formed and semantically legal?".
# `lint` answers "is this config a GOOD IDEA?" -- advisory warnings that never
# block generation. Operates on parsed MV_NODE_* arrays.

# Emit advisory warnings. Returns 0 if clean, 1 if any warning was emitted.
mv_lint_fleet() {
    if [ "$MV_NODE_COUNT" -eq 0 ]; then
        mv_err "no nodes to lint"
        return 2
    fi
    local warns=0 i

    # A single-node fleet has nothing to peer with.
    if [ "$MV_NODE_COUNT" -eq 1 ]; then
        mv_warn "fleet has a single node — no peers will be generated"
        warns=$((warns + 1))
    fi

    for ((i = 0; i < MV_NODE_COUNT; i++)); do
        local name="${MV_NODE_NAME[i]}"
        local overlay="${MV_NODE_OVERLAY[i]}"
        local allowed="${MV_NODE_ALLOWED[i]}"

        # Overlay host addresses should use /32 (v4) or /128 (v6); a wider prefix
        # advertises a whole subnet from a single node, which is usually a mistake.
        case "$overlay" in
            */32|*/128) : ;;
            */*)
                mv_warn "node '$name': overlay_ip '$overlay' is not a /32 or /128 host address"
                warns=$((warns + 1))
                ;;
        esac

        # A node advertising 0.0.0.0/0 is a default-route exit; flag it so it is
        # a deliberate choice, not an accident.
        case ",$allowed," in
            *",0.0.0.0/0,"*|*",::/0,"*)
                mv_warn "node '$name': advertises a default route (0.0.0.0/0 or ::/0) — full-tunnel exit node?"
                warns=$((warns + 1))
                ;;
        esac

        # Recommend a keepalive when behind NAT (endpoint is a private RFC1918 host).
        case "${MV_NODE_ENDPOINT[i]}" in
            10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*)
                if [ -z "${MV_NODE_KEEPALIVE[i]}" ]; then
                    mv_warn "node '$name': private endpoint but no persistent_keepalive — set one for NAT traversal"
                    warns=$((warns + 1))
                fi
                ;;
        esac
    done

    if [ "$warns" -gt 0 ]; then
        mv_warn "$warns lint warning(s) (advisory; does not block generate)"
        return 1
    fi
    mv_info "lint: no advisories"
    return 0
}
