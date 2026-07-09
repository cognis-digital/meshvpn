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

# Return success if $1 is a syntactically plausible IPv6 address.
# Accepts full and '::'-compressed forms. Not a canonicaliser; a sanity gate.
mv_is_ipv6() {
    local ip="$1"
    [ -n "$ip" ] || return 1
    # Must contain a colon and only hex digits, colons.
    case "$ip" in
        *:*) : ;;
        *) return 1 ;;
    esac
    case "$ip" in
        *[!0-9A-Fa-f:]*) return 1 ;;
    esac
    # At most one '::' compression.
    local rest="${ip#*::}"
    if [ "$rest" != "$ip" ]; then
        case "$rest" in
            *::*) return 1 ;;
        esac
    fi
    # Each hextet at most 4 chars. Split on ':' and check.
    local IFS=':'
    # shellcheck disable=SC2206
    local parts=($ip)
    unset IFS
    local h
    for h in "${parts[@]}"; do
        [ -z "$h" ] && continue           # from '::'
        [ "${#h}" -le 4 ] || return 1
    done
    return 0
}

# Return success if $1 is a valid IPv6 CIDR like fd00::/64 (prefix 0-128).
mv_is_cidr6() {
    local cidr="$1"
    case "$cidr" in
        */*) : ;;
        *) return 1 ;;
    esac
    local addr="${cidr%%/*}"
    local pfx="${cidr#*/}"
    [ "${addr}/${pfx}" = "$cidr" ] || return 1
    mv_is_ipv6 "$addr" || return 1
    case "$pfx" in
        ''|*[!0-9]*) return 1 ;;
    esac
    if [ "${#pfx}" -gt 1 ] && [ "${pfx:0:1}" = "0" ]; then
        return 1
    fi
    [ "$pfx" -le 128 ]
}

# Return success if $1 is a valid IPv4 OR IPv6 CIDR.
mv_is_any_cidr() {
    mv_is_cidr "$1" || mv_is_cidr6 "$1"
}

# JSON-escape a string on stdout (quotes, backslashes, control chars).
mv_json_escape() {
    local s="$1" out="" c i bs=$'\\'
    for ((i = 0; i < ${#s}; i++)); do
        c="${s:i:1}"
        case "$c" in
            '"')     out="$out$bs\"" ;;
            "$bs")   out="$out$bs$bs" ;;
            $'\t')   out="${out}${bs}t" ;;
            $'\n')   out="${out}${bs}n" ;;
            *)       out="$out$c" ;;
        esac
    done
    printf '%s' "$out"
}
