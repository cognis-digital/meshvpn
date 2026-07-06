# meshvpn architecture

meshvpn is a pure-shell pipeline over a small, line-oriented fleet config. It
turns a compact description of an overlay network into per-node WireGuard config
files, topology graphs, and reachability checks — **without ever handling real
key material**.

```
 fleet.conf ─► config.sh (parse) ─► MV_NODE_* arrays ─┬─► validate.sh ─► pass/fail
                                                        ├─► lint.sh     ─► advisories
                                                        ├─► generate.sh ─► wgN.conf (placeholder keys)
                                                        ├─► graph.sh    ─► dot / mermaid / ascii
                                                        ├─► export.sh   ─► JSON
                                                        ├─► keygen.sh   ─► out-of-band key helper script
                                                        └─► healthcheck.sh ─► targets / advisory probe
```

## Modules

| File | Responsibility |
|------|----------------|
| `meshvpn.sh` | Entrypoint: resolves its own real path (symlink-safe), sources `lib/`, parses options, dispatches subcommands, owns exit codes. |
| `lib/common.sh` | Logging (`mv_info`/`mv_warn`/`mv_err`), `mv_trim`, small helpers. |
| `lib/netutil.sh` | Clean-room validators: IPv4/IPv6 literals, IPv4/IPv6 CIDR, endpoint host, port, and a JSON string escaper. No shelling out to `ipcalc`/`python`. |
| `lib/config.sh` | The line-oriented parser. Fills the parallel `MV_NODE_*` arrays and global defaults. Rejects structural errors early. |
| `lib/validate.sh` | Semantic validation: required fields, unique names, overlay-IP collisions, valid CIDRs, and optional-field ranges (mtu, keepalive, dns, group). |
| `lib/lint.sh` | Advisory best-practice warnings (host-prefix width, default-route exit, NAT keepalive). Never blocks. |
| `lib/generate.sh` | Emits `wgN.conf` per node for the `mesh`/`hub`/`partial` topologies. Every key is a placeholder. |
| `lib/graph.sh` | Renders the peering graph as Graphviz DOT, Mermaid, or plain-text adjacency. |
| `lib/export.sh` | Serialises the parsed fleet to JSON (topology only, no keys). |
| `lib/keygen.sh` | Emits an out-of-band `wg genkey` helper script for an operator to run themselves. |
| `lib/healthcheck.sh` | Lists endpoint targets; optional advisory `/dev/tcp` probe; JSON output. |

## Data model

The parser is deliberately dependency-free. Instead of an object model it uses
**parallel arrays** indexed by node position:

```
MV_NODE_NAME[i]  MV_NODE_ENDPOINT[i]  MV_NODE_OVERLAY[i]  MV_NODE_ALLOWED[i]
MV_NODE_DNS[i]   MV_NODE_MTU[i]       MV_NODE_KEEPALIVE[i] MV_NODE_GROUP[i]
```

The **first** node (index 0) is the hub for the `hub` and `partial` topologies.

## Topologies

- **mesh** — every node peers with every other (`N·(N−1)/2` edges).
- **hub** — node 0 peers with all; spokes peer only with the hub.
- **partial** — node 0 is a hub that peers with all; other nodes additionally
  peer with nodes that share their non-empty `group` label. This gives an
  intra-region mesh plus a cross-region hub without a full `N²` mesh.

`generate` and `graph` share one predicate, `_mv_peers`, so a rendered graph
always matches the configs that would be generated.

## Key handling (the hard line)

meshvpn **never generates, reads, or stores real private keys.** Every emitted
`[Interface]` carries `PrivateKey = <FILL_FROM_SECRET: wg genkey>` and every
`[Peer]` a `PublicKey = <FILL_PUBKEY:name>` placeholder. `keygen` only *prints* a
helper script for an operator to run out of band. The test suite asserts that no
44-char base64 key ever appears in generated output, and the shipped
`.gitignore` blocks `*.private`/`*.key`/`*.pem`.

## Exit codes

- `0` success · `1` semantic/validation failure or advisory (lint) · `2` usage error.
