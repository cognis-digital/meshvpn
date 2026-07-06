# meshvpn

**A dependency-free WireGuard overlay deploy helper** — validate a fleet, generate per-node configs, graph the topology, and healthcheck endpoints, all from one compact config. Pure POSIX-ish Bash. It **never generates, reads, or stores real private keys.**

[![ci](https://github.com/cognis-digital/meshvpn/actions/workflows/ci.yml/badge.svg)](https://github.com/cognis-digital/meshvpn/actions/workflows/ci.yml)
![lang](https://img.shields.io/badge/lang-Bash-4EAA25)
![license](https://img.shields.io/badge/license-COCL%201.0-2ea043)

Part of the **[Cognis Neural Suite](https://github.com/cognis-digital)**.

## The problem

Standing up a WireGuard overlay across a fleet means hand-writing one `wgN.conf` per node, getting the peer lists right, and keeping key material out of git. meshvpn takes a single line-oriented fleet description and does the mechanical parts — **validate → generate → graph → healthcheck** — while refusing to touch a private key. You mint keys out of band with `wg genkey` and inject them from your secret store; meshvpn only scaffolds placeholders.

- No runtime dependency beyond a shell. No `python`, no `ipcalc`, no network at build time.
- Never writes real keys. The bundled `.gitignore` blocks `*.private`/`*.key`/`*.pem`.
- Infrastructure / defensive scope only.

## Commands

| Command | What it does |
|---|---|
| `validate` | Parse + semantically validate the fleet (`--json` for machine output). |
| `lint` | Advisory best-practice warnings (host-prefix width, default-route exit, NAT keepalive). |
| `generate` | Emit `wgN.conf` per node for `mesh` / `hub` / `partial` topologies (placeholder keys). |
| `graph` | Render the peering topology as `dot` / `mermaid` / `ascii`. |
| `export` | Emit the parsed fleet as JSON (topology only, no keys). |
| `keygen` | Print an out-of-band `wg genkey` helper script (meshvpn never runs it). |
| `healthcheck` | List endpoint targets; `--dry-run` (no network) or `--json`; advisory TCP probe otherwise. |

## Config format

Line-oriented; `#` comments and blank lines ignored. The **first** `[node]` is the hub for `hub`/`partial`. Optional per-node fields: `dns`, `mtu`, `persistent_keepalive`, `group`.

```ini
listen_port = 51820                       # optional global default
persistent_keepalive = 25                 # optional global default

[node]
name        = berlin
endpoint    = berlin.example.net:51820     # public host:port (WireGuard is UDP)
overlay_ip  = 10.66.0.1/32                 # this node's overlay address
allowed_ips = 10.66.0.1/32                 # routes advertised to peers
```

See [`examples/fleet.conf`](examples/fleet.conf) (four nodes) and [`examples/datacenter.conf`](examples/datacenter.conf) (two-region `partial` topology with `dns`/`mtu`/`group`).

## Example output (real, captured)

Graphing the hub topology of the bundled example:

```
$ meshvpn graph --config examples/fleet.conf --topology hub
meshvpn topology: hub (4 nodes)
  berlin           [hub] -> 3 peer(s): oslo lisbon tokyo
  oslo             -> 1 peer(s): berlin
  lisbon           -> 1 peer(s): berlin
  tokyo            -> 1 peer(s): berlin
```

Generating a mesh — note the key **placeholders**, never real keys:

```
$ meshvpn generate --config examples/fleet.conf --topology mesh --out ./out
$ sed -n '9,20p' out/wg0.conf
[Interface]
# berlin overlay address
Address = 10.66.0.1/32
ListenPort = 51820
PrivateKey = <FILL_FROM_SECRET: wg genkey>

[Peer]
# peer: oslo
PublicKey = <FILL_PUBKEY:oslo>
Endpoint = oslo.example.net:51820
AllowedIPs = 10.66.0.2/32
PersistentKeepalive = 25
```

Exporting the fleet as JSON:

```
$ meshvpn export --config examples/fleet.conf | head -8
{
  "fleet": {
    "node_count": 4,
    "listen_port_default": 51820,
    "keepalive_default": 25
  },
  "nodes": [
    { "name": "berlin", "endpoint": "berlin.example.net:51820", ...
```

## Topologies

- **mesh** — every node peers with every other.
- **hub** — the first node is the hub; spokes peer only with it.
- **partial** — the first node is a hub that peers with all; other nodes also peer within their shared `group` label (intra-region mesh + cross-region hub, without a full N² mesh).

`generate` and `graph` share the same peering predicate, so a rendered graph always matches the configs that would be generated.

## Why placeholders, not keys

Generating private keys inside a deploy helper invites them into version control, CI logs, and shared scratch dirs. meshvpn refuses. Mint keys out of band and inject from your secret store:

```sh
wg genkey | tee berlin.private | wg pubkey > berlin.public
# then substitute berlin.private into wg0.conf via your secret manager
```

`meshvpn keygen --config <file>` prints a ready-to-review script that does exactly this for every node — but **meshvpn never runs it and never sees the output**.

## Install

### Linux / macOS
```sh
./install.sh                 # installs a `meshvpn` wrapper into ~/.local/bin
meshvpn --help
```

### Windows
meshvpn is a POSIX shell tool; run it under **Git Bash**, **WSL**, or **MSYS2**.
```powershell
./install.ps1                # drops a meshvpn.cmd wrapper on PATH that calls bash
```

### Docker
```sh
docker build -t meshvpn .
docker run --rm -v "$PWD:/work" meshvpn validate --config /work/examples/fleet.conf
```

### Make
```sh
make check                   # shellcheck + tests
make demo                    # end-to-end demo
```

## Tests & demo

```sh
bash tests/run.sh            # 47 assertions, fully offline (no WireGuard, no network)
bash examples/demo.sh        # runnable end-to-end demo
```

The suite covers validate (well-formed + duplicate name, overlay collision, bad CIDR/port/MTU/DNS, IPv6), lint advisories, generate for **mesh/hub/partial** (peer counts, placeholder presence, optional-field propagation, and an assertion that **no real base64 key** ever appears), graph in all three formats, export/keygen, and healthcheck dry-run + JSON. CI runs `shellcheck` plus the suite and demo on **Ubuntu and macOS**.

## Architecture

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Security notes

- No real key material is ever produced or handled.
- `validate` rejects malformed input before any config is emitted; `generate` refuses to run on an invalid fleet.
- The live `healthcheck` probe is a best-effort TCP hint — WireGuard is UDP, so a closed TCP port does **not** prove a node is down. Treat live results as advisory.

## License

COCL 1.0 — see [LICENSE](LICENSE). Commercial use → licensing@cognis.digital
