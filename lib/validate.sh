# shellcheck shell=bash
# meshvpn - semantic validation of a parsed fleet config
# Maintainer: Cognis Digital
# License: COCL 1.0
#
# Assumes mv_config_parse has already populated the MV_NODE_* arrays.
# Checks: at least one node; unique names; unique overlay IPs (collision check);
# valid endpoint host:port; valid overlay CIDR; valid allowed_ips CIDR list.

# Validate the currently parsed fleet. Prints every problem found to stderr.
# Returns 0 if clean, 1 if any error was detected.
mv_validate_fleet() {
    local errors=0
    local i j

    if [ "$MV_NODE_COUNT" -eq 0 ]; then
        mv_err "fleet has no nodes"
        return 1
    fi

    # Per-node field checks.
    for ((i = 0; i < MV_NODE_COUNT; i++)); do
        local name="${MV_NODE_NAME[i]}"
        local endpoint="${MV_NODE_ENDPOINT[i]}"
        local overlay="${MV_NODE_OVERLAY[i]}"
        local allowed="${MV_NODE_ALLOWED[i]}"
        local label="node #$((i + 1))"
        [ -n "$name" ] && label="node '$name'"

        # name required.
        if [ -z "$name" ]; then
            mv_err "$label: missing 'name'"
            errors=$((errors + 1))
        else
            case "$name" in
                *[!a-zA-Z0-9._-]*)
                    mv_err "node '$name': name has invalid characters (use a-z 0-9 . _ -)"
                    errors=$((errors + 1))
                    ;;
            esac
        fi

        # endpoint required: host:port.
        if [ -z "$endpoint" ]; then
            mv_err "$label: missing 'endpoint'"
            errors=$((errors + 1))
        else
            local ehost eport
            ehost="$(mv_endpoint_host "$endpoint")"
            eport="$(mv_endpoint_port "$endpoint")"
            if [ -z "$eport" ]; then
                mv_err "$label: endpoint must be host:port (got '$endpoint')"
                errors=$((errors + 1))
            else
                if ! mv_is_endpoint_host "$ehost"; then
                    mv_err "$label: invalid endpoint host '$ehost'"
                    errors=$((errors + 1))
                fi
                if ! mv_is_port "$eport"; then
                    mv_err "$label: invalid endpoint port '$eport'"
                    errors=$((errors + 1))
                fi
            fi
        fi

        # overlay_ip required: a CIDR.
        if [ -z "$overlay" ]; then
            mv_err "$label: missing 'overlay_ip'"
            errors=$((errors + 1))
        elif ! mv_is_cidr "$overlay"; then
            mv_err "$label: invalid overlay_ip CIDR '$overlay'"
            errors=$((errors + 1))
        fi

        # allowed_ips required: comma-separated CIDR list.
        if [ -z "$allowed" ]; then
            mv_err "$label: missing 'allowed_ips'"
            errors=$((errors + 1))
        else
            local IFS=','
            # shellcheck disable=SC2206
            local cidrs=($allowed)
            unset IFS
            local c trimmed
            for c in "${cidrs[@]}"; do
                trimmed="$(mv_trim "$c")"
                [ -z "$trimmed" ] && continue
                if ! mv_is_cidr "$trimmed"; then
                    mv_err "$label: invalid allowed_ips CIDR '$trimmed'"
                    errors=$((errors + 1))
                fi
            done
        fi
    done

    # Uniqueness: names.
    for ((i = 0; i < MV_NODE_COUNT; i++)); do
        for ((j = i + 1; j < MV_NODE_COUNT; j++)); do
            if [ -n "${MV_NODE_NAME[i]}" ] && [ "${MV_NODE_NAME[i]}" = "${MV_NODE_NAME[j]}" ]; then
                mv_err "duplicate node name '${MV_NODE_NAME[i]}'"
                errors=$((errors + 1))
            fi
        done
    done

    # Uniqueness: overlay IP address (compare the address part, ignore prefix).
    for ((i = 0; i < MV_NODE_COUNT; i++)); do
        local ai="${MV_NODE_OVERLAY[i]%%/*}"
        [ -z "$ai" ] && continue
        for ((j = i + 1; j < MV_NODE_COUNT; j++)); do
            local aj="${MV_NODE_OVERLAY[j]%%/*}"
            [ -z "$aj" ] && continue
            if [ "$ai" = "$aj" ]; then
                mv_err "overlay-IP collision: '${MV_NODE_NAME[i]}' and '${MV_NODE_NAME[j]}' both use $ai"
                errors=$((errors + 1))
            fi
        done
    done

    if [ "$errors" -gt 0 ]; then
        mv_err "$errors problem(s) found"
        return 1
    fi
    return 0
}
