# Security Posture

> To report a vulnerability in this repo's tooling, see [`SECURITY.md`](../SECURITY.md)
> at the repo root. This document is the threat model and control mapping.

## Threat model (in scope)

1. Compromised container image (supply-chain attack).
2. Compromised container process (RCE, dependency CVE).
3. Stolen device credentials (lost laptop, leaked pre-auth key).
4. Malicious tenant on the tailnet (lateral movement).
5. MITM (TLS downgrade, DERP eavesdropping).
6. UI reconnaissance (random people probing the login page).

## Controls

| Threat | Control |
|---|---|
| Supply chain | Both images built from source at pinned tags. `-trimpath` (Go), `npm ci --ignore-scripts` (UI). Trivy CI gate on both. Optionally pin by digest (`image.digest` / `ui.image.digest` / `postgresql.image.digest` in `values.yaml`, resolved via `make pin-digests`) for immutable, tag-mutation-proof deploys. |
| Post-exploit lateral (API) | Distroless base — no shell / package manager / libc. |
| Post-exploit lateral (UI) | nginx-unprivileged (UID 101), read-only rootfs, capabilities dropped, tmpfs for writable paths. |
| Container escape | `runAsNonRoot`, `readOnlyRootFilesystem`, `capDrop: ALL`, `seccompProfile: RuntimeDefault`. |
| Namespace escape | PodSecurity `restricted` at namespace level. |
| UI reconnaissance | Optional Basic Auth on `/web` via a **separate Ingress** — API path untouched, Tailscale clients unaffected. |
| Lost pre-auth key | `hs-add-device` defaults: 1-use, 24h-TTL keys. |
| Stolen device | `headscale nodes delete -i <id>` removes from all peers' maps immediately. |
| Lateral movement post-join | ACL policy is **deny-by-default**; sample uses group-based least privilege + Tailscale SSH `check` mode. |
| MITM | TLS via cert-manager, HSTS + strict security headers in Caddy/nginx, `grpc_allow_insecure: false`. |
| Client telemetry | `logtail.enabled: false` — clients don't send logs to Tailscale Inc. |
| Compromised DB pod | NetworkPolicy allows ingress only from headscale + backup pods; egress only to DNS. |
| Compromised UI pod | NetworkPolicy allows ingress only from ingress controller; egress only to DNS. Browser talks to API directly. |

## Secrets

Nothing sensitive is baked into any image.

| Secret | Purpose | Source |
|---|---|---|
| `noise_private.key` | Server Noise handshake | PVC — auto-generated on first boot |
| `derp_private.key` | Server DERP relay key | PVC — auto-generated on first boot |
| DB password | Postgres auth | K8s Secret (chart-generated / your Secret / Vault via VSO) |
| UI Basic Auth htpasswd | UI ingress auth | K8s Secret (chart-generated bcrypt or your existingSecret) |
| `policy.hujson` | ACL policy | ConfigMap (non-secret) |
| Pre-auth keys | Device onboarding | DB-only, ephemeral |
| UI API key | Per-user UI auth | Browser localStorage only — never sent server-side |

## DB password priority chain

Same Deployment template regardless of source:

1. `vault.enabled: true` → VSO writes a K8s Secret from Vault KV
2. `postgresql.external.enabled: true` → `existingSecret` required
3. `postgresql.auth.existingSecret` set → your Secret
4. Default → chart auto-generates a 32-char password, retained via `helm.sh/resource-policy: keep`

## UI Basic Auth details

- Applied via `nginx.ingress.kubernetes.io/auth-{type,realm,secret}` on the `ui-ingress` resource **only**.
- Passwords bcrypt-hashed by Sprig's `htpasswd` at chart render time.
- Rotation: change `ui.basicAuth.password`, `helm upgrade`. The `checksum/ui-auth` annotation on the UI Ingress forces nginx to reload with new credentials.
- Multi-user: bring your own Secret with an htpasswd file; set `ui.basicAuth.existingSecret`.
- Basic Auth is a **first hurdle**, not real user auth — the real gate is the per-user API key each user pastes into Settings after logging in.

## Vault integration (optional)

- VSO holds Vault tokens in memory only; the sync destination Secret is a regular K8s Secret (etcd-encrypted if you've enabled that).
- Rotation in Vault → VSO updates the K8s Secret → `rolloutRestart` on Postgres + headscale automatically.
- Namespace-level Secret RBAC still applies — Vault doesn't magic that away.

## Key rotation

- **Pre-auth keys**: 24 h TTL default, single-use.
- **DB password**: rotate in Vault (VSO auto-rolls) or `kubectl edit secret` + roll.
- **Server Noise key**: schedule maintenance, regenerate, restart. Clients re-handshake automatically.
- **TLS cert**: cert-manager rotates automatically.
- **UI Basic Auth**: `helm upgrade --set-string ui.basicAuth.password=NEW`.

## Auditing

- CLI ops flow through the API — JSON-logged.
- Prometheus metrics: `headscale_node_registrations_total`, `headscale_preauthkey_used_total`, `headscale_apikeys_used_total`.
- Ship logs to Loki/OpenSearch; alert on new user / preauth key / API key creation outside change windows and failed-auth spikes.

## Deliberately excluded

- **No shell in the API container.** Debug via `kubectl logs` + metrics + DB inspection from a sidecar pod, not `kubectl exec sh`.
- **No gRPC exposed to the internet.** `grpc_listen_addr` binds inside the pod only; use `kubectl port-forward` for remote CLI.
- **No SSO on the UI (yet).** Basic Auth is a low-friction first hurdle. If you need real SSO, `oauth2-proxy` in front of the UI Ingress is the natural next step.
