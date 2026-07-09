# shellcheck shell=bash
# meshvpn - endpoint healthcheck
# Maintainer: Cognis Digital
# License: COCL 1.0
#
# Probes each node's public endpoint. With --dry-run it only LISTS the
# host:port targets (no network calls at all), which is what the test suite
# and air-gapped reviews rely on. A live probe uses bash's /dev/tcp when
# available purely to test reachability of the UDP port's host; it never
# transmits WireGuard traffic or touches keys.

# List endpoint targets, one "name<TAB>host:port" per line.
# Requires MV_NODE_* parsed.
mv_healthcheck_targets() {
    local i
    for ((i = 0; i < MV_NODE_COUNT; i++)); do
        local name="${MV_NODE_NAME[i]}"
        local endpoint="${MV_NODE_ENDPOINT[i]}"
        printf '%s\t%s\n' "$name" "$endpoint"
    done
}

# Dry-run healthcheck: print the targets without any network activity.
mv_healthcheck_dry_run() {
    if [ "$MV_NODE_COUNT" -eq 0 ]; then
        mv_err "no nodes to check"
        return 2
    fi
    mv_info "healthcheck targets (dry-run, no network):"
    local i
    for ((i = 0; i < MV_NODE_COUNT; i++)); do
        printf '  %-16s %s\n' "${MV_NODE_NAME[i]}" "${MV_NODE_ENDPOINT[i]}"
    done
    return 0
}

# Live healthcheck: attempt a TCP connect to each endpoint host:port using
# bash /dev/tcp with a short timeout. This is a best-effort reachability hint
# only; WireGuard itself is UDP, so a closed TCP port does not imply the node
# is down. Returns the count of unreachable nodes via exit status (capped 1).
mv_healthcheck_live() {
    if [ "$MV_NODE_COUNT" -eq 0 ]; then
        mv_err "no nodes to check"
        return 2
    fi
    local unreachable=0
    local i
    for ((i = 0; i < MV_NODE_COUNT; i++)); do
        local name="${MV_NODE_NAME[i]}"
        local endpoint="${MV_NODE_ENDPOINT[i]}"
        local host port
        host="$(mv_endpoint_host "$endpoint")"
        port="$(mv_endpoint_port "$endpoint")"
        if mv_tcp_probe "$host" "$port"; then
            printf '  [ ok ] %-16s %s\n' "$name" "$endpoint"
        else
            printf '  [fail] %-16s %s\n' "$name" "$endpoint"
            unreachable=$((unreachable + 1))
        fi
    done
    if [ "$unreachable" -gt 0 ]; then
        mv_warn "$unreachable endpoint(s) unreachable (note: WireGuard is UDP; TCP probe is advisory)"
        return 1
    fi
    return 0
}

# Best-effort TCP reachability probe via bash /dev/tcp with a timeout.
# Returns 0 on connect, non-zero otherwise. Pure bash; no nc/curl dependency.
mv_tcp_probe() {
    local host="$1" port="$2"
    [ -n "$host" ] && [ -n "$port" ] || return 1
    # 'timeout' may not exist everywhere; degrade gracefully.
    if command -v timeout >/dev/null 2>&1; then
        timeout 3 bash -c ": >/dev/tcp/$host/$port" >/dev/null 2>&1
    else
        ( : >"/dev/tcp/$host/$port" ) >/dev/null 2>&1
    fi
}

# Emit healthcheck targets as JSON (no network probe). Requires MV_NODE_*.
mv_healthcheck_json() {
    if [ "$MV_NODE_COUNT" -eq 0 ]; then
        mv_err "no nodes to check"
        return 2
    fi
    local i
    printf '{\n  "targets": [\n'
    for ((i = 0; i < MV_NODE_COUNT; i++)); do
        local host port
        host="$(mv_endpoint_host "${MV_NODE_ENDPOINT[i]}")"
        port="$(mv_endpoint_port "${MV_NODE_ENDPOINT[i]}")"
        printf '    { "name": "%s", "host": "%s", "port": "%s" }' \
            "$(mv_json_escape "${MV_NODE_NAME[i]}")" \
            "$(mv_json_escape "$host")" \
            "$(mv_json_escape "$port")"
        if [ "$i" -eq $((MV_NODE_COUNT - 1)) ]; then printf '\n'; else printf ',\n'; fi
    done
    printf '  ]\n}\n'
    return 0
}
