# 🦭 headscale-setup

[![build-image](https://github.com/eslam-adel92/headscale-setup/actions/workflows/build-image.yml/badge.svg)](https://github.com/eslam-adel92/headscale-setup/actions/workflows/build-image.yml)
[![validate](https://github.com/eslam-adel92/headscale-setup/actions/workflows/validate.yml/badge.svg)](https://github.com/eslam-adel92/headscale-setup/actions/workflows/validate.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](LICENSE)
[![Helm](https://img.shields.io/badge/Helm-%E2%89%A53.14-0F1689)](helm/headscale)
[![Docker Compose](https://img.shields.io/badge/Docker%20Compose-v2-2496ED)](compose/docker-compose.yml)

> Production-grade, security-hardened, self-hosted **Tailscale coordination
> server** with an optional web UI (Basic-Auth-protected), PostgreSQL,
> optional Vault integration, Trivy-gated CI, and one-command device onboarding.

Runs anywhere from a laptop (`docker compose up`) to a Kubernetes cluster
(Helm chart with 22 templates, ArgoCD-ready). Nothing is tied to any specific
organisation — swap `eslam-adel92` in a couple of places and go.

## Table of contents

- [Requirements](#-requirements)
- [Deployment modes](#-deployment-modes)
- [What's inside](#-whats-inside)
- [What to change before first run](#-what-to-change-before-first-run)
- [Quickstart — Docker Compose](#-quickstart--docker-compose)
- [Quickstart — Kubernetes (Helm)](#-quickstart--kubernetes-helm)
- [CI/CD](#-cicd)
- [Feature matrix](#-feature-matrix)
- [Design decisions](#-design-decisions)
- [Common ops](#-common-ops)
- [Troubleshooting](#-troubleshooting)
- [Further reading](#-further-reading)
- [Contributing](#-contributing)

---

## 📋 Requirements

| Tool | Needed for | Minimum version |
|---|---|---|
| Docker Engine + Compose plugin | Compose mode | Compose v2 (`docker compose`, not `docker-compose`) — `profiles:` support |
| Docker Buildx | Building images locally | Bundled with recent Docker Desktop/Engine |
| Helm | Helm mode | ≥ 3.14 |
| `kubectl` | Helm mode | Matching your cluster's minor version |
| A Kubernetes cluster | Helm mode | ≥ 1.27 (see `kubeVersion` in `Chart.yaml`) |
| `jq` (optional) | `scripts/hs-add-device` — robust JSON parsing | any recent version |
| `qrencode` (optional) | `scripts/hs-add-device` — inline QR code | any recent version |
| `trivy` (optional) | `make scan` / `make scan-ui` locally | any recent version |

Cluster-specific prerequisites (cert-manager, ingress-nginx, a UDP-capable
LoadBalancer, VSO) are listed in [Quickstart — Kubernetes](#-quickstart--kubernetes-helm).

---

## 🚢 Deployment modes

| Mode | DB | Web UI | UI Basic Auth | Secrets | Use case |
|---|---|---|---|---|---|
| 🧪 **Compose lab** | Bundled PG16 (+ optional daily pg_dump) | On, with Caddy basic-auth (env-var opt-in) | Caddy `basic_auth` | `.env` file | Local, self-contained, ≤ 20 devices |
| 🚀 **Helm (small)** | Bundled Postgres StatefulSet + CronJob backups | Opt-in | ingress-nginx annotations (chart-generated Secret) | Auto-gen K8s Secret | ≤ 100 devices, one cluster |
| 🏢 **Helm (managed)** | External Postgres (RDS / Cloud SQL / Autonomous DB) | Opt-in | ingress-nginx + your Secret (multi-user htpasswd) | **Vault via VSO** (opt-in) | Multi-AZ, ArgoCD-managed |

---

## 📦 What's inside

```
headscale-setup/
├── .github/
│   ├── workflows/build-image.yml        ← Matrix Trivy-gated build → GHCR
│   │                                       (headscale + headscale-ui)
│   ├── workflows/validate.yml           ← helm lint/template, compose config, shellcheck
│   ├── ISSUE_TEMPLATE/                  ← Bug report / feature request
│   └── PULL_REQUEST_TEMPLATE.md
├── docker/
│   ├── Dockerfile                       ← headscale — distroless/static:nonroot (~28 MB)
│   └── ui/
│       ├── Dockerfile                   ← headscale-ui — nginx-unprivileged (~30 MB)
│       └── nginx.conf                   ←   serves /web + /healthz, SPA fallback
├── compose/                             ← Full stack: Postgres, headscale, UI, Caddy
│   ├── docker-compose.yml
│   ├── .env.example                     ←   incl. UI_BASIC_AUTH_* toggles
│   ├── caddy/Caddyfile                  ←   /web/* (opt-in Basic Auth) + /* → API
│   ├── config/{config.yaml, policy.hujson}
│   └── postgres/{postgresql.conf, pg_hba.conf, initdb.d/}
├── k8s/base/
│   ├── namespace.yaml                   ← PodSecurity: restricted
│   └── argocd-application.yaml
├── helm/headscale/                      ← Full Helm chart
│   ├── Chart.yaml
│   ├── values.yaml                      ←   the single control panel
│   └── templates/
│       ├── deployment.yaml              ←   headscale + wait-for-postgres init
│       ├── service.yaml, ingress.yaml   ←   API on /, NO auth (clients need anon)
│       ├── networkpolicy.yaml           ←   same-namespace ingress by default
│       ├── pdb.yaml, rbac.yaml, hpa.yaml, servicemonitor.yaml
│       ├── postgresql-*.yaml (6 files)  ←   StatefulSet, ConfigMap, Secret,
│       │                                    Services, NetworkPolicy, backup CronJob
│       ├── ui-deployment.yaml
│       ├── ui-service.yaml
│       ├── ui-networkpolicy.yaml
│       ├── ui-ingress.yaml              ←   Separate Ingress for /web with basic-auth
│       ├── ui-basic-auth-secret.yaml    ←   Chart-generated bcrypt htpasswd Secret
│       ├── vault-secret.yaml            ←   VaultStaticSecret (VSO)
│       ├── configmap.yaml               ←   headscale config + ACL policy
│       ├── tests/test-connection.yaml   ←   `helm test` hook, hits /health
│       └── NOTES.txt
├── scripts/
│   ├── hs-add-device                    ← 🌟 auto-detects compose/k8s, prints
│   │                                       tailscale up cmd + QR + deep-link
│   └── hs-hash-ui-password              ←   bcrypt hasher for Compose Basic Auth
├── clients/AGENT_INSTALL.md             ← Fedora / Ubuntu / Arch / macOS / Win / iOS / Android
├── docs/
│   ├── ARCHITECTURE.md
│   ├── SECURITY.md
│   ├── SCALING.md
│   ├── DATABASE.md
│   ├── VAULT.md
│   ├── WEB_UI.md
│   └── UI_BASIC_AUTH.md
├── Makefile                             ← all the make targets you'll want
├── CHANGELOG.md                         ← what changed release-to-release
├── LICENSE                              ← BSD-3-Clause
├── SECURITY.md                          ← how to report a vulnerability
├── CONTRIBUTING.md                      ← how to propose changes
├── .gitignore
└── README.md                            ← you are here
```

---

## 🔧 What to change before first run

Search-and-replace these placeholders. That's it — there's nothing else
hardcoded to any specific environment.

| Placeholder | Where | Replace with |
|---|---|---|
| `eslam-adel92` | `helm/headscale/values.yaml`, `compose/.env.example`, `Makefile`, `k8s/base/argocd-application.yaml` | Your GitHub org / GHCR namespace |
| `hs.example.com` | `helm/headscale/values.yaml`, `compose/.env.example` | Your public FQDN for headscale |
| `admin@example.com` | `compose/.env.example` | Let's Encrypt registration email |
| `hs.internal` | `helm/headscale/values.yaml`, `compose/config/config.yaml`, `docker/config/config.yaml` | Your MagicDNS base domain (any private domain) |
| `letsencrypt` | `helm/headscale/values.yaml → ingress.annotations` | Your cert-manager `ClusterIssuer` name |
| `https://github.com/eslam-adel92/headscale-setup.git` | `k8s/base/argocd-application.yaml` | Your fork URL |

Quick bulk-replace (Linux/macOS):
```bash
grep -rl "eslam-adel92"        . | xargs sed -i 's/eslam-adel92/my-real-org/g'
grep -rl "hs.example.com"  . | xargs sed -i 's/hs.example.com/hs.yourdomain.com/g'
grep -rl "admin@example.com" . | xargs sed -i 's/admin@example.com/ops@yourdomain.com/g'
```

Every other setting — DERP region name, ACL user names (`admin`, `alice`, `bob`),
timezone (`UTC`), DB name/user (`headscale`), Vault path (`apps/headscale/postgres`)
— is a safely generic default you can leave alone or override per environment.

**Optional — pin images by digest.** `values.yaml` has an empty
`image.digest` / `ui.image.digest` / `postgresql.image.digest` next to each
`tag:`. Run `make pin-digests` to resolve the current digest for each
configured ref, then set it (via `values-{env}.yaml` or `--set-string`) for
immutable, tag-mutation-proof deploys. Leave empty to deploy by tag (default,
unchanged behavior).

---

## ⚡ Quickstart — Docker Compose

```bash
# 1. Build both images (or pull from GHCR once CI has run)
docker buildx build -t ghcr.io/eslam-adel92/headscale:0.29.2        docker/
docker buildx build -t ghcr.io/eslam-adel92/headscale-ui:2026.03.17 docker/ui/

# 2. Configure
cp compose/.env.example compose/.env
$EDITOR compose/.env                       # set HEADSCALE_DOMAIN, ACME_EMAIL, POSTGRES_PASSWORD

# Optionally enable UI Basic Auth
./scripts/hs-hash-ui-password 'yourPassword'
# → paste output into compose/.env as UI_BASIC_AUTH_HASH

# 3. Boot the stack
cd compose && docker compose up -d
docker compose --profile backup up -d      # + daily pg_dump

# 4. Onboard your first device
../scripts/hs-add-device alice --tags tag:laptop

# 5. Open the web UI
open https://<HEADSCALE_DOMAIN>/web        # → paste an API key into Settings
```

---

## 🚢 Quickstart — Kubernetes (Helm)

```bash
# Lint + preview
helm lint helm/headscale
helm template headscale helm/headscale -f helm/headscale/values.yaml

# Install with Basic Auth enabled on the UI
helm upgrade --install headscale ./helm/headscale \
  --namespace headscale --create-namespace \
  -f helm/headscale/values.yaml \
  --set image.repository=ghcr.io/eslam-adel92/headscale \
  --set ui.image.repository=ghcr.io/eslam-adel92/headscale-ui \
  --set server.url=https://hs.yourdomain.com \
  --set ingress.host=hs.yourdomain.com \
  --set ui.basicAuth.enabled=true \
  --set-string ui.basicAuth.password="$(openssl rand -base64 24)"

# Or GitOps via ArgoCD (put overrides in values-prod.yaml under .gitignore)
kubectl apply -f k8s/base/argocd-application.yaml
```

Cluster prereqs:
- **cert-manager** with a `ClusterIssuer` (default expected name: `letsencrypt`)
- **ingress-nginx** (or set `ingress.className`)
- A **RWO StorageClass**
- A **UDP-capable LoadBalancer** for STUN 3478
- Vault integration additionally needs **hashicorp/vault-secrets-operator**

---

## 🔨 CI/CD

`.github/workflows/build-image.yml` runs a **matrix build** for both images:

1. Build amd64 locally, load into daemon.
2. **Trivy scan** — CRITICAL + HIGH, `ignore-unfixed: true`. Fails the run on findings.
3. Upload SARIF to GitHub → Security → Code scanning (categorised per image).
4. On scan pass → multi-arch build (amd64 + arm64) → push to GHCR.

**Triggers**: `workflow_dispatch` (with knobs for versions / push / fail-on-vuln),
push to `main` touching `docker/**`, and tag `v*.*.*` (semver-tagged release).

**One-time GitHub setting**: Repo Settings → Actions → General → Workflow permissions → **Read and write permissions**.

**Auth**: uses the built-in `GITHUB_TOKEN` — no PAT needed. Least-privilege scoping via the workflow's `permissions:` block (`packages: write`, `security-events: write`, `id-token: write`).

Images land at:
- `ghcr.io/<eslam-adel92>/headscale:0.29.2` (+ `latest`, `sha-abcdef1`, semver tags on git tags)
- `ghcr.io/<eslam-adel92>/headscale-ui:2026.03.17` (same tag policy)

---

## ✅ Feature matrix

| Feature | Compose | Helm | Config knob |
|---|---|---|---|
| Headscale API | ✅ | ✅ | `image.repository`, `image.tag` |
| PostgreSQL (bundled) | ✅ | ✅ | `postgresql.enabled` |
| PostgreSQL (external) | via `HEADSCALE_DATABASE_POSTGRES_*` env | ✅ | `postgresql.external.*` |
| Automated backups | Profile `backup` | ✅ CronJob | `postgresql.backup.*` |
| Web UI (headscale-ui) | ✅ | ✅ | `ui.enabled` |
| UI Basic Auth | ✅ (env var) | ✅ (chart-generated or existingSecret) | `ui.basicAuth.*` |
| Vault via VSO | ❌ | ✅ | `vault.enabled` |
| TLS termination | Caddy + Let's Encrypt | ingress-nginx + cert-manager | `ingress.*` |
| Metrics (Prometheus) | Exposed on `:9090` | ServiceMonitor | `metrics.serviceMonitor.*` |
| NetworkPolicy | n/a | ✅ default-deny | `networkPolicy.*` |
| Same-namespace ingress | n/a | ✅ default | `networkPolicy.ingressController.namespace: ""` |
| PDB | n/a | ✅ | `podDisruptionBudget.*` |
| Multi-arch images | Local build only | ✅ CI multi-arch | Workflow matrix |
| Trivy scan gate | ❌ (local via `make scan`) | ❌ (local) | CI workflow |
| Device onboarding | `hs-add-device` | `hs-add-device` (auto-detects k8s) | — |

---

## 🎯 Design decisions

1. **Two Ingress resources on the same host.** API (`/`) is always anonymous — Tailscale clients need that. UI (`/web`) has its own Ingress so `nginx.ingress.kubernetes.io/auth-*` annotations apply only there. ingress-nginx merges rules from multiple Ingresses on the same host and honours the more-specific path.
2. **Same-namespace ingress by default.** NetworkPolicy uses a `podSelector` (no `namespaceSelector`) when `networkPolicy.ingressController.namespace: ""`. Kubernetes' default same-namespace semantics apply. Set the namespace explicitly if your controller lives elsewhere.
3. **Both images built from source, hardened runtimes.** `distroless/static:nonroot` for API, `nginx-unprivileged` for UI. `-trimpath` (Go), `npm ci --ignore-scripts` (UI). Both Trivy-scanned in CI.
4. **Read-only rootfs for both containers.** UI uses tmpfs mounts for nginx's writable paths (`/var/cache/nginx`, `/var/run`, `/tmp`). API is fully read-only.
5. **PostgreSQL bundled but replaceable.** `postgres:16-alpine` for standalone; two-flag switch (`postgresql.enabled=false` + `postgresql.external.enabled=true`) for managed DB.
6. **Every DB knob is a values key.** `postgresql.config.*` renders directly into `postgresql.conf`. Add/remove keys freely, no rebuild.
7. **Vault opt-in.** Same Deployment template regardless of secret source. VSO writes a K8s Secret; workloads consume it via `secretKeyRef`. Rotation triggers `rolloutRestart` automatically.
8. **Basic Auth is a first hurdle, not user auth.** Real access control is the per-user API key stored in browser localStorage.
9. **Honest scaling story.** Headscale core is single-writer (network-map recomputation is CPU-bound and not shardable). HPA is disabled by default for the API. UI and DERP relays scale horizontally.
10. **Easy device onboarding.** `hs-add-device` auto-detects Compose/K8s/binary, creates the user if needed, generates a 24h-TTL pre-auth key, prints a `tailscale up …` command + QR code + `tailscale://` deep-link + UI URL.

---

## 🧑‍💻 Common ops

```bash
# List users / nodes / pre-auth keys
kubectl -n headscale exec deploy/headscale -- headscale nodes list
docker compose exec headscale headscale users list

# Delete a lost/stolen device
headscale nodes delete --identifier 42

# Rotate ACL policy — edit values.yaml → helm upgrade → checksum triggers rollout
helm upgrade headscale ./helm/headscale -f values-prod.yaml

# Rotate UI Basic Auth password
helm upgrade headscale ./helm/headscale --reuse-values \
  --set-string ui.basicAuth.password="$(openssl rand -base64 24)"

# Grab latest DB backup
make pg-backup                              # triggers a one-off Job
BP=$(kubectl -n headscale get pod -l app.kubernetes.io/component=backup -o name | tail -1)
kubectl -n headscale cp "$BP":/backups/headscale-<ts>.dump ./

# Restore
make pg-restore FILE=./headscale-20260101T020000Z.dump

# Add a device (via Make)
make add-device USER=alice TAGS=tag:laptop
```

Run `make help` for the full list.

---

## 🛠 Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Caddy stuck / cert never issues (Compose) | ACME HTTP-01 challenge can't reach you — DNS for `HEADSCALE_DOMAIN` not pointing at this host yet, or port 80 blocked/NAT'd | `dig +short $HEADSCALE_DOMAIN` and confirm it resolves publicly to this box; open port 80 (not just 443) to the internet during issuance |
| `postgres` container unhealthy / headscale restarts in a loop (Compose) | First boot is slow to `pg_isready` (initdb + WAL setup), or `POSTGRES_PASSWORD` unset | `docker compose logs postgres`; confirm `.env` has `POSTGRES_PASSWORD` set — it's a hard requirement (`:?` in the compose file) |
| `wait-for-postgres` init container never completes (Helm) | Bundled Postgres StatefulSet pod not Ready yet, or `postgresql.external.*` misconfigured while `postgresql.enabled` is also true | `kubectl -n headscale logs deploy/headscale -c wait-for-postgres`; check `kubectl -n headscale get pods -l app.kubernetes.io/name=postgresql`; make sure exactly one of `postgresql.enabled` / `postgresql.external.enabled` is `true` |
| Browser gets a 401 on `/web` right after enabling Basic Auth | Stale ingress/Caddy config, or credentials rotated but not reloaded | Helm: confirm `checksum/ui-auth` annotation changed and the UI ingress/pod rolled; Compose: `docker compose restart caddy` after regenerating `UI_BASIC_AUTH_HASH` |
| `hs-add-device` exits with "Could not detect a running headscale" | None of binary/K8s pod/Compose service was found from the auto-detection order | Set `HS_BIN`, or run from the repo root / `compose/` so the fallback paths resolve; see `scripts/hs-add-device`'s detection order in `CLAUDE.md` |
| `hs-add-device` exits with "Could not determine numeric ID" | Neither `jq` nor `python3` is installed | Install `jq` (recommended) — see [Requirements](#-requirements) |

For anything not listed here, check the relevant doc in
[Further reading](#-further-reading) — most failure modes are covered by the
threat model, scaling ceilings, or DB tuning docs.

---

## 📚 Further reading

| Doc | What it covers |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Component diagram, data flow, two-Ingress model, why STUN needs its own LB |
| [`docs/SECURITY.md`](docs/SECURITY.md) | Threat model, control mapping, secret handling, UI-specific controls |
| [`docs/SCALING.md`](docs/SCALING.md) | The honest limits, ceilings by device count, what scales horizontally |
| [`docs/DATABASE.md`](docs/DATABASE.md) | Postgres image choice, tuning knobs, backup/restore, external DB |
| [`docs/VAULT.md`](docs/VAULT.md) | VSO integration, seed, enable, rotate |
| [`docs/WEB_UI.md`](docs/WEB_UI.md) | UI overview, API-key first sign-in, custom vs. upstream image |
| [`docs/UI_BASIC_AUTH.md`](docs/UI_BASIC_AUTH.md) | Basic Auth walkthrough (Compose + Helm), rotation, multi-user |
| [`clients/AGENT_INSTALL.md`](clients/AGENT_INSTALL.md) | Fedora / Ubuntu / Arch / macOS / Windows / iOS / Android |
| [`SECURITY.md`](SECURITY.md) | How to report a vulnerability in this repo's tooling |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How to propose changes, what to validate before opening a PR |
| [`CHANGELOG.md`](CHANGELOG.md) | What changed release-to-release |

Upstream projects:
- Headscale: <https://github.com/juanfont/headscale> · <https://headscale.net>
- Headscale-UI: <https://github.com/gurucomputing/headscale-ui>

---

## 🤝 Contributing

This is deployment tooling around upstream headscale/headscale-ui, not an
app with its own test suite — see [`CONTRIBUTING.md`](CONTRIBUTING.md) for
what to run (`helm lint`, `helm template`, `docker compose config`, `bash -n`)
before opening a PR, and [`SECURITY.md`](SECURITY.md) if you're reporting a
vulnerability rather than a bug.

---

## 📄 License

[BSD-3-Clause](LICENSE) (matches both upstream projects).
