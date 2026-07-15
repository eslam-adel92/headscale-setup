# Architecture

## 30-second mental model

```
                        ┌───────────────────────────┐
                        │        Internet           │
                        └──────┬──────────────┬─────┘
                               │              │
                ┌──────────────▼───┐   ┌──────▼────────────┐
                │ Ingress (nginx)  │   │ UDP 3478 (STUN)   │
                │ TLS via cert-mgr │   │ LoadBalancer      │
                │                  │   │                   │
                │ /web/*  →  UI    │   │                   │
                │  ↑ optional      │   │                   │
                │  Basic Auth      │   │                   │
                │                  │   │                   │
                │ /*      →  API   │   │                   │
                └───────┬──────┬───┘   └──────┬────────────┘
                        │      │              │
             ┌──────────▼──┐   │              │
             │ headscale-ui│   │              │
             │  (nginx)    │   │              │
             │  UID 101    │   │              │
             │ read-only FS│   │              │
             └─────────────┘   ▼              ▼
                    ┌─────────────────────────────────┐
                    │       headscale pod             │
                    │  distroless/static UID 65532    │
                    │  ┌────────┐  ┌────────────────┐ │
                    │  │  API   │  │ embedded DERP  │ │
                    │  │ :8080  │  │ (or dedicated) │ │
                    │  └────────┘  └────────────────┘ │
                    └─────────┬───────────────────────┘
                              ▼
              ┌──────────────────────────────┐
              │  PostgreSQL StatefulSet      │
              │  (postgres:16-alpine, UID 70)│
              └──────────────┬───────────────┘
                             ▼
              ┌──────────────────────────────┐
              │  pg_dump CronJob → PVC       │
              │  (retention: 14d default)    │
              └──────────────────────────────┘

  Actual VPN traffic is peer-to-peer WireGuard between clients.
  Headscale never sees the payload — only the coordination handshake.
  The UI is a static SPA — API calls happen browser → headscale directly.
```

## Data flow

1. **Registration**: `tailscale up --login-server https://…` → HTTPS to the headscale API → OIDC-style browser flow or pre-auth key (what `hs-add-device` generates).
2. **Node map delivery**: headscale computes and streams the world map (peers + ACL-derived allow-list + DERP relays) over a long-lived HTTPS stream.
3. **P2P WireGuard**: clients try direct connections; if NATs prevent it, they relay through the DERP server.
4. **MagicDNS**: clients resolve `hostname.<base_domain>` locally from the node map — no upstream DNS needed for tailnet peers.
5. **Web UI**: browser fetches the static SPA from `/web`; SPA calls the headscale API on the same origin — **no CORS, no server-side proxy**.

## Two Ingress resources, one host

ingress-nginx merges rules from multiple Ingresses on the same host and honours per-Ingress annotations. That's how we scope Basic Auth to the UI only without breaking Tailscale clients:

| Ingress resource | Path | Auth |
|---|---|---|
| `<release>-headscale` | `/` → API | **none** (clients need anonymous access) |
| `<release>-headscale-ui` | `/web` → UI | **optional Basic Auth annotations** |

## NetworkPolicy: same-namespace ingress by default

`networkPolicy.ingressController.namespace: ""` (default) means the ingress controller lives in the same namespace as the release. The rendered NetworkPolicy uses a **pod-only selector** (`app.kubernetes.io/name: ingress-nginx`) — no `namespaceSelector`, so Kubernetes' default same-namespace semantics apply.

Cross-namespace? Set:
```yaml
networkPolicy:
  ingressController:
    namespace: ingress-nginx
    podLabels:
      app.kubernetes.io/name: ingress-nginx
```

The helper `headscale.netpol.ingressControllerFrom` in `_helpers.tpl` emits the correct block either way.

## Why STUN needs its own LoadBalancer

STUN runs over UDP/3478 and needs its **public** IP to match the packet's source IP for hole-punching to work. HTTP ingress can't proxy UDP.

Solution: a separate `Service{type=LoadBalancer, protocol=UDP}` with `externalTrafficPolicy: Local` so the client IP is preserved.

## Scaling topology (large tailnet)

```
                ┌────────────┐    ┌────────────┐
                │  DERP #1   │    │  DERP #2   │   ← horizontal scale
                └─────┬──────┘    └─────┬──────┘     (DaemonSet + HPA)
                      │                  │
       ┌──────────────┼──────────────────┼──────────────┐
       │              ▼                  ▼              │
       │      ┌─────────────────────┐                   │
       │      │ headscale (1 pod)   │ ← SINGLE writer   │
       │      └─────────┬───────────┘                   │
       │                │                               │
       │      ┌─────────▼─────────┐                     │
       │      │  PostgreSQL HA    │ (managed DB)        │
       │      └───────────────────┘                     │
       └───────────────────────────────────────────────┘
```

## Component boundaries

| Component | Responsibility | Stateless? |
|---|---|---|
| headscale API | Auth, node map, gRPC CLI | ❌ (writes to DB) |
| DERP relay | STUN + fallback TCP relay when P2P fails | ✅ |
| headscale-ui | Static SPA — API calls happen in browser | ✅ |
| PostgreSQL StatefulSet | Persistent state (users, nodes, keys, policy) | ❌ |
| pg_dump CronJob | Automated backups | ✅ |
| Ingress controller | TLS termination + HTTP routing | ✅ |
| Vault Secrets Operator | Vault → K8s Secret sync (opt-in) | ✅ |
