# shellcheck shell=bash
# meshvpn - export the parsed fleet as machine-readable JSON
# Maintainer: Cognis Digital
# License: COCL 1.0
#
# Emits the parsed MV_NODE_* arrays as a JSON document on stdout. No key
# material is ever included -- this is the fleet topology only. Consumers can
# pipe this into jq, an IaC pipeline, or a dashboard.

# Emit the fleet as JSON. Requires MV_NODE_* already parsed.
mv_export_json() {
    if [ "$MV_NODE_COUNT" -eq 0 ]; then
        mv_err "no nodes to export"
        return 2
    fi
    local i
    printf '{\n'
    printf '  "fleet": {\n'
    printf '    "node_count": %s,\n' "$MV_NODE_COUNT"
    printf '    "listen_port_default": %s,\n' "$MV_LISTEN_PORT_DEFAULT"
    printf '    "keepalive_default": %s\n' "$MV_KEEPALIVE_DEFAULT"
    printf '  },\n'
    printf '  "nodes": [\n'
    for ((i = 0; i < MV_NODE_COUNT; i++)); do
        printf '    {\n'
        printf '      "name": "%s",\n' "$(mv_json_escape "${MV_NODE_NAME[i]}")"
        printf '      "endpoint": "%s",\n' "$(mv_json_escape "${MV_NODE_ENDPOINT[i]}")"
        printf '      "overlay_ip": "%s",\n' "$(mv_json_escape "${MV_NODE_OVERLAY[i]}")"
        printf '      "allowed_ips": "%s",\n' "$(mv_json_escape "${MV_NODE_ALLOWED[i]}")"
        printf '      "dns": "%s",\n' "$(mv_json_escape "${MV_NODE_DNS[i]}")"
        printf '      "mtu": "%s",\n' "$(mv_json_escape "${MV_NODE_MTU[i]}")"
        printf '      "keepalive": "%s",\n' "$(mv_json_escape "${MV_NODE_KEEPALIVE[i]}")"
        printf '      "group": "%s",\n' "$(mv_json_escape "${MV_NODE_GROUP[i]}")"
        printf '      "is_hub": %s\n' "$([ "$i" -eq 0 ] && echo true || echo false)"
        if [ "$i" -eq $((MV_NODE_COUNT - 1)) ]; then
            printf '    }\n'
        else
            printf '    },\n'
        fi
    done
    printf '  ]\n'
    printf '}\n'
    return 0
}
