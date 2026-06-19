# shellcheck shell=bash
# meshvpn - common helpers
# Maintainer: Cognis Digital
# License: COCL 1.0
#
# Shared logging and small utilities. Sourced by the other lib files and the
# main entrypoint. No real key material is ever generated or read here.

# Emit an error line to stderr.
mv_err() {
    printf 'error: %s\n' "$*" >&2
}

# Emit a warning line to stderr.
mv_warn() {
    printf 'warning: %s\n' "$*" >&2
}

# Emit an informational line to stdout.
mv_info() {
    printf '%s\n' "$*"
}

# Trim leading/trailing whitespace from $1, echo the result.
mv_trim() {
    local s="$1"
    # Strip leading whitespace.
    s="${s#"${s%%[![:space:]]*}"}"
    # Strip trailing whitespace.
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Return success if $1 appears in the remaining args.
mv_contains() {
    local needle="$1"; shift
    local item
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}
