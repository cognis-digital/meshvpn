# shellcheck shell=bash
# meshvpn - render the peering topology as a graph
# Maintainer: Cognis Digital
# License: COCL 1.0
#
# Produces a visual representation of who peers with whom under a given
# topology, in Graphviz DOT, Mermaid, or a plain-text adjacency listing.
# Pure computation over MV_NODE_* -- no keys, no network.

# Return 0 if node i peers with node j under $topology (i != j).
_mv_peers() {
    local topology="$1" i="$2" j="$3"
    [ "$i" -ne "$j" ] || return 1
    case "$topology" in
        mesh) return 0 ;;
        hub)
            # peer iff one of them is the hub (node 0)
            { [ "$i" -eq 0 ] || [ "$j" -eq 0 ]; } && return 0
            return 1
            ;;
        partial)
            { [ "$i" -eq 0 ] || [ "$j" -eq 0 ]; } && return 0
            local gi="${MV_NODE_GROUP[i]}" gj="${MV_NODE_GROUP[j]}"
            [ -n "$gi" ] && [ "$gi" = "$gj" ] && return 0
            return 1
            ;;
        *) return 1 ;;
    esac
}

# Emit a Graphviz DOT graph of the topology.
mv_graph_dot() {
    local topology="$1"
    local i j
    printf 'graph meshvpn {\n'
    printf '  layout=neato; node [shape=box, style=rounded];\n'
    for ((i = 0; i < MV_NODE_COUNT; i++)); do
        local label="${MV_NODE_NAME[i]}"
        [ "$i" -eq 0 ] && label="$label\\n(hub)"
        printf '  "%s" [label="%s"];\n' "${MV_NODE_NAME[i]}" "$label"
    done
    for ((i = 0; i < MV_NODE_COUNT; i++)); do
        for ((j = i + 1; j < MV_NODE_COUNT; j++)); do
            if _mv_peers "$topology" "$i" "$j"; then
                printf '  "%s" -- "%s";\n' "${MV_NODE_NAME[i]}" "${MV_NODE_NAME[j]}"
            fi
        done
    done
    printf '}\n'
}

# Emit a Mermaid graph of the topology (renders on GitHub / docs).
mv_graph_mermaid() {
    local topology="$1"
    local i j
    printf 'graph TD\n'
    for ((i = 0; i < MV_NODE_COUNT; i++)); do
        local label="${MV_NODE_NAME[i]}"
        [ "$i" -eq 0 ] && label="$label (hub)"
        printf '  n%s["%s"]\n' "$i" "$label"
    done
    for ((i = 0; i < MV_NODE_COUNT; i++)); do
        for ((j = i + 1; j < MV_NODE_COUNT; j++)); do
            if _mv_peers "$topology" "$i" "$j"; then
                printf '  n%s --- n%s\n' "$i" "$j"
            fi
        done
    done
}

# Emit a plain-text adjacency listing (no external renderer needed).
mv_graph_ascii() {
    local topology="$1"
    local i j
    printf 'meshvpn topology: %s (%s nodes)\n' "$topology" "$MV_NODE_COUNT"
    for ((i = 0; i < MV_NODE_COUNT; i++)); do
        local peers="" count=0
        for ((j = 0; j < MV_NODE_COUNT; j++)); do
            if _mv_peers "$topology" "$i" "$j"; then
                peers="$peers ${MV_NODE_NAME[j]}"
                count=$((count + 1))
            fi
        done
        local tag=""
        [ "$i" -eq 0 ] && tag=" [hub]"
        printf '  %-16s%s -> %d peer(s):%s\n' "${MV_NODE_NAME[i]}" "$tag" "$count" "$peers"
    done
}

# Dispatch by --format (dot|mermaid|ascii). Default ascii.
mv_graph() {
    local topology="$1" format="$2"
    if [ "$MV_NODE_COUNT" -eq 0 ]; then
        mv_err "no nodes to graph"
        return 2
    fi
    case "$topology" in
        mesh|hub|partial) : ;;
        *) mv_err "unknown topology '$topology' (use mesh, hub, or partial)"; return 2 ;;
    esac
    case "${format:-ascii}" in
        dot)     mv_graph_dot "$topology" ;;
        mermaid) mv_graph_mermaid "$topology" ;;
        ascii|text) mv_graph_ascii "$topology" ;;
        *) mv_err "unknown graph format '$format' (use dot, mermaid, or ascii)"; return 2 ;;
    esac
    return 0
}
