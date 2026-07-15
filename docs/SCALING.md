# Scaling

Read this before you enable HPA on the headscale core.

## The bottleneck

Headscale's cost function is **network-map recomputations**, not RPS. Every node change triggers a rebuild of the whole world map + diff push to every connected client.

- Single-threaded per event
- O(nodes × edges) in the ACL graph
- CPU-bound
- **Not shardable** — one writer must own the state

## Ceilings (rules of thumb)

| Devices | Churn | Topology |
|---|---|---|
| < 50 | any | 1 replica, embedded DERP, 100m/128Mi |
| 50–200 | low (servers) | 1 replica, Postgres, 500m/256Mi |
| 50–200 | high (laptops/phones) | 1 replica, Postgres, dedicated DERP, 1 CPU / 512Mi |
| 200–500 | mixed | Bigger box, Postgres, DERP DaemonSet + HPA |
| > 500 or heavy churn | | Outside Headscale's design envelope — Tailscale SaaS or split into multiple tailnets |

## What scales horizontally

- **DERP relays** — stateless UDP + TCP relays. `derp.embedded: false` in the chart lets you split them out.
- **headscale-ui** — completely stateless. Raise `ui.replicaCount` freely.
- **PostgreSQL read replicas** — not used by headscale today, but useful for backup/analytics.

## What does NOT scale horizontally

- **Headscale core.** Two writers = corrupted state. `autoscaling.enabled: false` is the default; the chart guards against this.

## Vertical scaling

```yaml
resources:
  requests: { cpu: 500m,  memory: 256Mi }
  limits:   { cpu: 4000m, memory: 1Gi }
```

Headscale is single-threaded per event but the Go runtime uses multiple cores for parallel event handling. 2–4 vCPU helps a lot when many nodes churn simultaneously.

## Dedicated DERP relays

For > 200 devices:

```yaml
derp:
  embedded: false
```

Then deploy `tailscale/derper` separately (Deployment/DaemonSet), register its URL under `derp.urls`. DERPs need public IPs + open UDP/3478 + TCP/443.

## Metrics to watch

- `headscale_map_response_generation_seconds` — P99 should stay under 500 ms
- `headscale_map_response_write_seconds` — P99 should stay under 1 s
- `headscale_node_count` — track growth
- Pod CPU throttling > 1% → size up

## Capacity test recipe

Simulate 2× target device count with `tailscale/tailscale` sidecar pods, cycle them on/off every 5 min. If P99 map response > 2 s, size up.
