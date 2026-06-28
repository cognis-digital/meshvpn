# meshvpn

A small, dependency-free **deploy helper and healthcheck** for a WireGuard-style
overlay network across a private fleet. From a compact fleet config it
**validates** the topology, **generates** per-node WireGuard config files, and
**probes** endpoints for reachability.

meshvpn is pure Bash. It has no runtime dependencies beyond a POSIX-ish shell,
and it deliberately **never generates, reads, or stores real private keys** --
it scaffolds key *placeholders* and documents the standard out-of-band
`wg genkey` workflow. Infrastructure / defensive scope only.

- Maintainer: **Cognis Digital**
- License: **COCL 1.0**


<!-- cognis:example:start -->
## 🔎 Example output

**Sample result format** _(illustrative values — run on your own data for real findings):_

```
{
"nodes": [
  {
    "id": "node-1",
    "ip": "192.168.1.100",
    "status": "online"
  },
  {
    "id": "node-2",
    "ip": "10.0.0.200",
    "status": "offline"
  },
  {
    "id": "node-3",
    "ip": "172.16.31.100",
    "status": "online"
  }
],
"edges": [
  {
    "from": "node-1",
    "to": "node-2",
    "status": "established"
  },
  {
    "from": "node-2",
    "to": "node-3",
    "status": "established"
  }
],
"summary": {
  "nodes_online": 2,
  "edges_established": 2
}
}
```

<!-- cognis:example:end -->

## Why placeholders, not keys

Generating private keys inside a deploy helper invites them into version
control, CI logs, and shared scratch dirs. meshvpn refuses to do that. Every
generated `[Interface]` carries:

```
PrivateKey = <FILL_FROM_SECRET: wg genkey>
```

and every `[Peer]` carries a per-node `PublicKey` placeholder like
`<FILL_PUBKEY:berlin>`. You mint real keys out-of-band and inject them from
your secret store:

```sh
wg genkey | tee berlin.private | wg pubkey > berlin.public
# then substitute berlin.private into wg0.conf via your secret manager
```

The bundled `.gitignore` blocks `*.private`, `*.key`, `*.pem`, etc. so key
material never gets committed by accident.

## Install

```sh
git clone <your-fork> meshvpn
cd meshvpn
chmod +x meshvpn.sh
./meshvpn.sh --help
```

## Config format

Line-oriented and clean-room (authored from the documented WireGuard config
model, not copied from any project). `#` starts a comment; blank lines are
ignored. The **first** `[node]` block is treated as the hub for hub-spoke.

```ini
listen_port = 51820            # optional global default (overridable per node)

[node]
name        = berlin
endpoint    = berlin.example.net:51820   # public host:port (WireGuard is UDP)
overlay_ip  = 10.66.0.1/32               # this node's overlay address
allowed_ips = 10.66.0.1/32               # routes this node advertises to peers
```

See [`examples/fleet.conf`](examples/fleet.conf) for a four-node fleet.

## Commands

### validate

```sh
./meshvpn.sh validate --config examples/fleet.conf
```

Parses the config and checks:

- at least one node
- unique node names
- no overlay-IP collisions (compares the address, ignoring prefix)
- valid endpoint `host:port` (IPv4 literal or DNS name; port 1-65535)
- valid `overlay_ip` CIDR and valid `allowed_ips` CIDR list

Exits **non-zero** if any problem is found (every problem is printed to stderr).

### generate

```sh
# full mesh: every node peers with every other
./meshvpn.sh generate --config examples/fleet.conf --topology mesh --out ./out

# hub-spoke: first node is the hub; spokes peer only with the hub
./meshvpn.sh generate --config examples/fleet.conf --topology hub --out ./out
```

Writes one `wgN.conf` per node (`wg0.conf`, `wg1.conf`, ...) where `wg0`
corresponds to the first node in the config. Each file contains:

- exactly one `[Interface]` block (`Address`, `ListenPort`, placeholder `PrivateKey`)
- one `[Peer]` block per peer (placeholder `PublicKey`, `Endpoint`, `AllowedIPs`,
  `PersistentKeepalive = 25`)

In **mesh**, every node gets `N-1` peers. In **hub**, the hub gets `N-1` peers
and each spoke gets exactly `1` (the hub). generate refuses to run on a config
that fails `validate`.

### healthcheck

```sh
# dry-run: list endpoint targets, NO network activity at all
./meshvpn.sh healthcheck --config examples/fleet.conf --dry-run

# live: best-effort advisory TCP reachability probe per endpoint
./meshvpn.sh healthcheck --config examples/fleet.conf
```

The live probe uses bash `/dev/tcp` only as a reachability hint. WireGuard is
UDP, so a closed TCP port does **not** prove a node is down -- treat live
results as advisory.

## Layout

```
meshvpn/
  meshvpn.sh              # entrypoint + subcommand dispatch
  lib/
    common.sh             # logging, trim, small helpers
    netutil.sh            # IPv4 / CIDR / port / endpoint-host validators
    config.sh             # pure-bash fleet config parser
    validate.sh           # semantic fleet validation
    generate.sh           # WireGuard config emitter (placeholders only)
    healthcheck.sh        # endpoint listing + advisory probe
  examples/
    fleet.conf            # authored 4-node example
  tests/
    run.sh                # self-contained suite (no WireGuard, no network)
  .github/workflows/ci.yml
  .gitignore
  README.md
```

## Tests

```sh
bash tests/run.sh
```

The suite runs entirely offline: it validates the example, generates mesh and
hub configs into a temp dir and asserts peer counts and placeholder presence
(and that **no real base64 private keys** appear), checks that bad configs
(duplicate name, overlay-IP collision, bad CIDR, missing field, bad port) fail
non-zero, and confirms `healthcheck --dry-run` lists every endpoint without any
network probe. The runner exits non-zero on any failure.

## Security notes

- No real key material is ever produced or handled.
- `validate` rejects malformed input before any config is emitted.
- `generate` will not run on an invalid fleet.
- `.gitignore` blocks common key file patterns.

License: COCL 1.0
