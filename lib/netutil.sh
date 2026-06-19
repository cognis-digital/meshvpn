# shellcheck shell=bash
# meshvpn - network sanity utilities (pure bash, no external tools)
# Maintainer: Cognis Digital
# License: COCL 1.0
#
# Validation helpers for IPv4 addresses and CIDR notation. These are
# clean-room implementations written against the dotted-quad / CIDR model;
# they do not shell out to ipcalc, python, or any third-party helper.

# Return success if $1 is a syntactically valid IPv4 dotted-quad (0-255 each).
mv_is_ipv4() {
    local ip="$1"
    local IFS='.'
    # Reject anything that is not exactly four parts.
    case "$ip" in
        *.*.*.*) : ;;
        *) return 1 ;;
    esac
    # shellcheck disable=SC2206
    local parts=($ip)
    [ "${#parts[@]}" -eq 4 ] || return 1
    local oct
    for oct in "${parts[@]}"; do
        # Must be all digits and non-empty.
        case "$oct" in
            ''|*[!0-9]*) return 1 ;;
        esac
        # Reject leading zeros like 01 or 007 (ambiguous / non-canonical),
        # but allow a bare "0".
        if [ "${#oct}" -gt 1 ] && [ "${oct:0:1}" = "0" ]; then
            return 1
        fi
        # Range 0-255.
        if [ "$oct" -gt 255 ]; then
            return 1
        fi
    done
    return 0
}

# Return success if $1 is a valid IPv4 CIDR like 10.0.0.0/24.
# Prefix length must be 0-32.
mv_is_cidr() {
    local cidr="$1"
    case "$cidr" in
        */*) : ;;
        *) return 1 ;;
    esac
    local addr="${cidr%%/*}"
    local pfx="${cidr#*/}"
    # Exactly one slash: rebuilding must match.
    [ "${addr}/${pfx}" = "$cidr" ] || return 1
    mv_is_ipv4 "$addr" || return 1
    case "$pfx" in
        ''|*[!0-9]*) return 1 ;;
    esac
    # Reject leading zeros in prefix (e.g. /08) except bare "0".
    if [ "${#pfx}" -gt 1 ] && [ "${pfx:0:1}" = "0" ]; then
        return 1
    fi
    if [ "$pfx" -gt 32 ]; then
        return 1
    fi
    return 0
}

# Return success if $1 is a plausible host:port or hostname/IP endpoint host.
# Accepts a DNS name or an IPv4 literal. Used for the public endpoint field.
mv_is_endpoint_host() {
    local host="$1"
    [ -n "$host" ] || return 1
    # IPv4 literal is fine.
    if mv_is_ipv4 "$host"; then
        return 0
    fi
    # Otherwise require a DNS-ish name: letters, digits, dot, hyphen.
    case "$host" in
        *[!a-zA-Z0-9.-]*) return 1 ;;
    esac
    # Must not start or end with a dot or hyphen.
    case "$host" in
        .*|-*|*.|*-) return 1 ;;
    esac
    return 0
}

# Return success if $1 is a valid TCP/UDP port (1-65535).
mv_is_port() {
    local p="$1"
    case "$p" in
        ''|*[!0-9]*) return 1 ;;
    esac
    if [ "${#p}" -gt 1 ] && [ "${p:0:1}" = "0" ]; then
        return 1
    fi
    [ "$p" -ge 1 ] && [ "$p" -le 65535 ]
}
