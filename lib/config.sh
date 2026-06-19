# shellcheck shell=bash
# meshvpn - fleet config parser & validator (pure bash)
# Maintainer: Cognis Digital
# License: COCL 1.0
#
# Config format (clean-room, line oriented). One "node" block per fleet member:
#
#   # comments start with '#', blank lines ignored
#   listen_port = 51820        # optional global default, overridable per node
#
#   [node]
#   name        = berlin
#   endpoint    = berlin.example.net:51820   # public host:port (UDP)
#   overlay_ip  = 10.66.0.1/32               # this node's address on the overlay
#   allowed_ips = 10.66.0.1/32               # routes advertised by this node
#
# Parsed nodes are exposed as parallel arrays:
#   MV_NODE_NAME[]  MV_NODE_ENDPOINT[]  MV_NODE_OVERLAY[]  MV_NODE_ALLOWED[]
# and MV_NODE_COUNT. The first declared node is treated as the hub for the
# hub-spoke topology.

# Parallel arrays populated by mv_config_parse.
MV_NODE_NAME=()
MV_NODE_ENDPOINT=()
MV_NODE_OVERLAY=()
MV_NODE_ALLOWED=()
MV_NODE_COUNT=0
MV_LISTEN_PORT_DEFAULT=51820

# Reset parser state. Useful for tests that parse multiple files in one process.
mv_config_reset() {
    MV_NODE_NAME=()
    MV_NODE_ENDPOINT=()
    MV_NODE_OVERLAY=()
    MV_NODE_ALLOWED=()
    MV_NODE_COUNT=0
    MV_LISTEN_PORT_DEFAULT=51820
}

# Parse a fleet config file into the MV_NODE_* arrays.
# Usage: mv_config_parse <file>
# Returns non-zero (and prints to stderr) on a structural parse error.
mv_config_parse() {
    local file="$1"
    mv_config_reset

    if [ -z "$file" ]; then
        mv_err "no config file given"
        return 2
    fi
    if [ ! -f "$file" ]; then
        mv_err "config file not found: $file"
        return 2
    fi

    local in_node=0
    local cur_name="" cur_endpoint="" cur_overlay="" cur_allowed=""
    local lineno=0
    local line key val raw

    # Flush the current node block into the arrays.
    _mv_flush_node() {
        [ "$in_node" -eq 1 ] || return 0
        MV_NODE_NAME+=("$cur_name")
        MV_NODE_ENDPOINT+=("$cur_endpoint")
        MV_NODE_OVERLAY+=("$cur_overlay")
        MV_NODE_ALLOWED+=("$cur_allowed")
        MV_NODE_COUNT=$((MV_NODE_COUNT + 1))
        cur_name=""; cur_endpoint=""; cur_overlay=""; cur_allowed=""
    }

    while IFS= read -r raw || [ -n "$raw" ]; do
        lineno=$((lineno + 1))
        # Strip trailing inline comments only when '#' is preceded by space,
        # so values containing '#' are unaffected (none expected, but safe).
        line="${raw%%#*}"
        line="$(mv_trim "$line")"
        [ -z "$line" ] && continue

        # Section header: [node]
        if [ "${line:0:1}" = "[" ]; then
            case "$line" in
                "[node]")
                    _mv_flush_node
                    in_node=1
                    ;;
                *)
                    mv_err "line $lineno: unknown section: $line"
                    return 2
                    ;;
            esac
            continue
        fi

        # key = value
        case "$line" in
            *=*) : ;;
            *)
                mv_err "line $lineno: expected 'key = value', got: $line"
                return 2
                ;;
        esac
        key="$(mv_trim "${line%%=*}")"
        val="$(mv_trim "${line#*=}")"

        if [ "$in_node" -eq 0 ]; then
            # Global (pre-node) settings.
            case "$key" in
                listen_port)
                    MV_LISTEN_PORT_DEFAULT="$val"
                    ;;
                *)
                    mv_err "line $lineno: unknown global key: $key"
                    return 2
                    ;;
            esac
            continue
        fi

        case "$key" in
            name)        cur_name="$val" ;;
            endpoint)    cur_endpoint="$val" ;;
            overlay_ip)  cur_overlay="$val" ;;
            allowed_ips) cur_allowed="$val" ;;
            *)
                mv_err "line $lineno: unknown node key: $key"
                return 2
                ;;
        esac
    done < "$file"

    _mv_flush_node
    unset -f _mv_flush_node

    if [ "$MV_NODE_COUNT" -eq 0 ]; then
        mv_err "config has no [node] blocks"
        return 2
    fi
    return 0
}

# Return the host portion of an "host:port" endpoint.
mv_endpoint_host() {
    local ep="$1"
    printf '%s' "${ep%:*}"
}

# Return the port portion of an "host:port" endpoint (empty if none).
mv_endpoint_port() {
    local ep="$1"
    case "$ep" in
        *:*) printf '%s' "${ep##*:}" ;;
        *)   printf '%s' "" ;;
    esac
}
