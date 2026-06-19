#!/usr/bin/env bash
# meshvpn - deploy helper + healthcheck for a WireGuard-style overlay fleet
# Maintainer: Cognis Digital
# License: COCL 1.0
#
# Generates per-node WireGuard config files (with key PLACEHOLDERS only),
# validates a fleet config, and probes endpoints. This tool deliberately
# NEVER generates or handles real private keys -- it scaffolds placeholders
# and documents the out-of-band `wg genkey` workflow. Infra/defensive scope.

set -u

# Resolve the directory this script lives in, so lib/ sourcing works from any cwd.
_mv_self="${BASH_SOURCE[0]}"
# Resolve one level of symlink without requiring readlink -f (portable).
while [ -h "$_mv_self" ]; do
    _mv_dir="$(cd -P "$(dirname "$_mv_self")" && pwd)"
    _mv_self="$(readlink "$_mv_self")"
    case "$_mv_self" in
        /*) : ;;
        *) _mv_self="$_mv_dir/$_mv_self" ;;
    esac
done
MV_ROOT="$(cd -P "$(dirname "$_mv_self")" && pwd)"

# shellcheck source=lib/common.sh
. "$MV_ROOT/lib/common.sh"
# shellcheck source=lib/netutil.sh
. "$MV_ROOT/lib/netutil.sh"
# shellcheck source=lib/config.sh
. "$MV_ROOT/lib/config.sh"
# shellcheck source=lib/validate.sh
. "$MV_ROOT/lib/validate.sh"
# shellcheck source=lib/generate.sh
. "$MV_ROOT/lib/generate.sh"
# shellcheck source=lib/healthcheck.sh
. "$MV_ROOT/lib/healthcheck.sh"

MV_VERSION="1.0.0"

mv_usage() {
    cat <<'EOF'
meshvpn - WireGuard-style overlay deploy helper & healthcheck (Cognis Digital)

USAGE:
  meshvpn.sh <command> [options]

COMMANDS:
  validate    --config <file>
              Parse and semantically validate a fleet config.
              Exits non-zero if any problem is found.

  generate    --config <file> --topology <mesh|hub> --out <dir>
              Emit one wgN.conf per node into <dir>. Each file has an
              [Interface] block plus [Peer] blocks. ALL keys are
              placeholders -- no real private keys are ever produced.
                mesh : every node peers with every other node.
                hub  : the first node in the config is the hub; spokes
                       peer only with the hub.

  healthcheck --config <file> [--dry-run]
              List endpoint targets. With --dry-run, performs NO network
              activity (just prints host:port targets). Without it, makes a
              best-effort advisory TCP reachability probe per endpoint.

  --help, -h  Show this help.
  --version   Show version.

KEY HANDLING (read this):
  meshvpn never creates or stores private keys. Generated [Interface]
  PrivateKey is the literal placeholder:
      <FILL_FROM_SECRET: wg genkey>
  Generate keys out-of-band and inject from your secret store:
      wg genkey | tee node.private | wg pubkey > node.public

CONFIG FORMAT:
  listen_port = 51820            # optional global default
  [node]
  name        = berlin
  endpoint    = berlin.example.net:51820
  overlay_ip  = 10.66.0.1/32
  allowed_ips = 10.66.0.1/32
  ... repeat [node] blocks ...

License: COCL 1.0
EOF
}

# Tiny flag parser shared by subcommands. Sets MV_OPT_<key> globals.
# Recognised: --config --topology --out --dry-run
_mv_parse_opts() {
    MV_OPT_CONFIG=""
    MV_OPT_TOPOLOGY=""
    MV_OPT_OUT=""
    MV_OPT_DRYRUN=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --config)
                [ "$#" -ge 2 ] || { mv_err "--config needs a value"; return 2; }
                MV_OPT_CONFIG="$2"; shift 2 ;;
            --config=*) MV_OPT_CONFIG="${1#*=}"; shift ;;
            --topology)
                [ "$#" -ge 2 ] || { mv_err "--topology needs a value"; return 2; }
                MV_OPT_TOPOLOGY="$2"; shift 2 ;;
            --topology=*) MV_OPT_TOPOLOGY="${1#*=}"; shift ;;
            --out)
                [ "$#" -ge 2 ] || { mv_err "--out needs a value"; return 2; }
                MV_OPT_OUT="$2"; shift 2 ;;
            --out=*) MV_OPT_OUT="${1#*=}"; shift ;;
            --dry-run) MV_OPT_DRYRUN=1; shift ;;
            *)
                mv_err "unknown option: $1"
                return 2 ;;
        esac
    done
    return 0
}

cmd_validate() {
    _mv_parse_opts "$@" || return 2
    if [ -z "$MV_OPT_CONFIG" ]; then
        mv_err "validate: --config <file> is required"
        return 2
    fi
    mv_config_parse "$MV_OPT_CONFIG" || return 1
    if mv_validate_fleet; then
        mv_info "OK: ${MV_NODE_COUNT} node(s) validated in '$MV_OPT_CONFIG'"
        return 0
    fi
    return 1
}

cmd_generate() {
    _mv_parse_opts "$@" || return 2
    if [ -z "$MV_OPT_CONFIG" ]; then
        mv_err "generate: --config <file> is required"
        return 2
    fi
    if [ -z "$MV_OPT_TOPOLOGY" ]; then
        mv_err "generate: --topology <mesh|hub> is required"
        return 2
    fi
    if [ -z "$MV_OPT_OUT" ]; then
        mv_err "generate: --out <dir> is required"
        return 2
    fi
    mv_config_parse "$MV_OPT_CONFIG" || return 1
    # Refuse to generate from an invalid fleet.
    if ! mv_validate_fleet; then
        mv_err "generate: refusing to generate from an invalid config"
        return 1
    fi
    mv_generate "$MV_OPT_TOPOLOGY" "$MV_OPT_OUT" || return 1
    mv_info "OK: generated ${MV_NODE_COUNT} config(s) (${MV_OPT_TOPOLOGY}) into '$MV_OPT_OUT'"
    return 0
}

cmd_healthcheck() {
    _mv_parse_opts "$@" || return 2
    if [ -z "$MV_OPT_CONFIG" ]; then
        mv_err "healthcheck: --config <file> is required"
        return 2
    fi
    mv_config_parse "$MV_OPT_CONFIG" || return 1
    if [ "$MV_OPT_DRYRUN" -eq 1 ]; then
        mv_healthcheck_dry_run
        return $?
    fi
    mv_healthcheck_live
    return $?
}

main() {
    if [ "$#" -eq 0 ]; then
        mv_usage
        return 2
    fi
    local cmd="$1"; shift
    case "$cmd" in
        validate)    cmd_validate "$@" ;;
        generate)    cmd_generate "$@" ;;
        healthcheck) cmd_healthcheck "$@" ;;
        --help|-h|help) mv_usage; return 0 ;;
        --version)   mv_info "meshvpn $MV_VERSION"; return 0 ;;
        *)
            mv_err "unknown command: $cmd"
            mv_usage >&2
            return 2 ;;
    esac
}

main "$@"
