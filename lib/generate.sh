# shellcheck shell=bash
# meshvpn - WireGuard config generator (key PLACEHOLDERS only)
# Maintainer: Cognis Digital
# License: COCL 1.0
#
# Emits one wgN.conf per node from the parsed MV_NODE_* arrays. Topology is
# "mesh" (every node peers with every other) or "hub" (first node is the hub;
# spokes peer only with the hub).
#
# SECURITY: this tool NEVER generates, reads, or writes real private keys.
# Every [Interface] PrivateKey is the literal placeholder shown below, and
# every [Peer] PublicKey is a per-node placeholder. Operators fill these in
# out-of-band with `wg genkey` / `wg pubkey` and a secret store. See README.

# Placeholder an operator must replace with the output of `wg genkey`.
MV_PRIVKEY_PLACEHOLDER='<FILL_FROM_SECRET: wg genkey>'

# Build the public-key placeholder for a given node name.
_mv_pubkey_placeholder() {
    printf '<FILL_PUBKEY:%s>' "$1"
}

# Sanitise a node name into a safe filename stem.
_mv_safe_stem() {
    local s="$1"
    s="${s//[^a-zA-Z0-9._-]/_}"
    printf '%s' "$s"
}

# Generate all node configs into a directory.
# Usage: mv_generate <topology mesh|hub> <out_dir>
# Requires MV_NODE_* already parsed. Returns non-zero on bad input.
mv_generate() {
    local topology="$1"
    local out_dir="$2"
    local i j

    case "$topology" in
        mesh|hub) : ;;
        *)
            mv_err "unknown topology '$topology' (use mesh or hub)"
            return 2
            ;;
    esac
    if [ -z "$out_dir" ]; then
        mv_err "no output directory given"
        return 2
    fi
    if [ "$MV_NODE_COUNT" -eq 0 ]; then
        mv_err "no nodes to generate"
        return 2
    fi

    mkdir -p "$out_dir" || {
        mv_err "cannot create output dir: $out_dir"
        return 2
    }

    for ((i = 0; i < MV_NODE_COUNT; i++)); do
        local name="${MV_NODE_NAME[i]}"
        local overlay="${MV_NODE_OVERLAY[i]}"
        local endpoint="${MV_NODE_ENDPOINT[i]}"
        local stem
        stem="$(_mv_safe_stem "$name")"
        local listen_port
        listen_port="$(mv_endpoint_port "$endpoint")"
        [ -z "$listen_port" ] && listen_port="$MV_LISTEN_PORT_DEFAULT"

        local conf="$out_dir/wg${i}.conf"

        {
            printf '# meshvpn generated config for node: %s\n' "$name"
            printf '# topology: %s\n' "$topology"
            printf '# Maintainer: Cognis Digital  |  License: COCL 1.0\n'
            printf '#\n'
            printf '# SECURITY: PrivateKey below is a PLACEHOLDER. Replace it out-of-band:\n'
            printf '#   wg genkey | tee %s.private | wg pubkey > %s.public\n' "$stem" "$stem"
            printf '# then inject the private key from your secret store. Never commit keys.\n'
            printf '\n'
            printf '[Interface]\n'
            printf '# %s overlay address\n' "$name"
            printf 'Address = %s\n' "$overlay"
            printf 'ListenPort = %s\n' "$listen_port"
            printf 'PrivateKey = %s\n' "$MV_PRIVKEY_PLACEHOLDER"
            printf '\n'

            for ((j = 0; j < MV_NODE_COUNT; j++)); do
                [ "$j" -eq "$i" ] && continue

                # Topology gate.
                if [ "$topology" = "hub" ]; then
                    # In hub-spoke: node 0 is the hub and peers with all.
                    # A spoke (i>0) peers ONLY with the hub (j==0).
                    if [ "$i" -ne 0 ] && [ "$j" -ne 0 ]; then
                        continue
                    fi
                fi

                local pname="${MV_NODE_NAME[j]}"
                local pendpoint="${MV_NODE_ENDPOINT[j]}"
                local pallowed="${MV_NODE_ALLOWED[j]}"

                printf '[Peer]\n'
                printf '# peer: %s\n' "$pname"
                printf 'PublicKey = %s\n' "$(_mv_pubkey_placeholder "$pname")"
                printf 'Endpoint = %s\n' "$pendpoint"
                printf 'AllowedIPs = %s\n' "$pallowed"
                printf 'PersistentKeepalive = 25\n'
                printf '\n'
            done
        } > "$conf" || {
            mv_err "failed writing $conf"
            return 2
        }

        mv_info "wrote $conf"
    done

    return 0
}
