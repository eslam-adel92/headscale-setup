# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Deployment tooling for a self-hosted Headscale (Tailscale coordination server) stack — not an application with its own source code. Headscale and headscale-ui are built from upstream source (`juanfont/headscale`, `gurucomputing/headscale-ui`) inside the Dockerfiles; this repo owns the Docker images, Compose stack, Helm chart, and onboarding scripts around them. There is no app-level test suite; "correctness" here means valid Helm/Compose manifests, images that build and pass the Trivy gate, and scripts that behave under `set -euo pipefail`.

Two deployment modes, sharing the same container images:
- **Docker Compose** (`compose/`) — Postgres + headscale + headscale-ui + Caddy (TLS via ACME), for a laptop or single box.
- **Kubernetes/Helm** (`helm/headscale/`) — full chart with 22 templates, optional bundled Postgres StatefulSet, optional Vault (VSO) secrets, ArgoCD-ready (`k8s/base/argocd-application.yaml`).

## Commands

```bash
make help                      # list all targets

# Images
make build / make build-ui     # local single-arch build (docker/, docker/ui/)
make push / make push-ui       # multi-arch build+push (needs buildx + registry auth)
make scan / make scan-ui       # trivy image --severity HIGH,CRITICAL --ignore-unfixed

# Compose
make compose-up                # cd compose && docker compose up -d
make compose-backup            # + pg_dump profile
make compose-down

# Helm
make helm-lint                 # helm lint helm/headscale
make helm-template             # helm template ... -f helm/headscale/values.yaml (render-only sanity check)
make helm-install / helm-uninstall

# Postgres (k8s)
make pg-shell                  # psql into the bundled StatefulSet
make pg-backup                 # trigger a one-off backup Job from the CronJob
make pg-restore FILE=./dump.dump

# Device onboarding
make add-device USER=alice [TAGS=tag:laptop]   # wraps scripts/hs-add-device
```

`scripts/hs-add-device` and `scripts/hs-hash-ui-password` are plain bash (`set -euo pipefail`). After editing either, sanity-check with `bash -n scripts/hs-add-device` and, if changing flag parsing or the Compose/K8s auto-detection logic, run it against a real local stack — there's no automated test for these.

There's no repo-wide lint/format command; validate changes with `helm lint` / `helm template` for chart edits, `docker build` (or `make build`) for Dockerfile edits, and `docker compose config` for Compose edits.

## Architecture

Full diagrams and rationale live in `docs/ARCHITECTURE.md`, `docs/SECURITY.md`, `docs/SCALING.md`, `docs/DATABASE.md`, `docs/VAULT.md`. Key things to know before editing:

**Two Ingress resources on one host (Helm).** `<release>-headscale` serves `/` → API with **no auth** (Tailscale clients need anonymous access). `<release>-headscale-ui` serves `/web` → UI with optional Basic Auth annotations. This split exists so `nginx.ingress.kubernetes.io/auth-*` annotations apply only to the UI path; ingress-nginx merges rules from multiple Ingresses on the same host. Don't collapse these into one Ingress.

**Compose does the same split via Caddy**, but with a twist: `compose/caddy/Caddyfile` (no auth) and `compose/caddy/Caddyfile.auth` (with `basic_auth`) are both mounted, and the container entrypoint picks one at boot based on whether `UI_BASIC_AUTH_HASH` is set — Caddy fails to parse an empty `basic_auth` block even behind a request-time matcher, so this can't be one file with a conditional.

**NetworkPolicy defaults to same-namespace ingress.** When `networkPolicy.ingressController.namespace: ""` (the default), the rendered policy uses a pod-only selector — no `namespaceSelector` — relying on Kubernetes' default same-namespace semantics. If the ingress controller lives elsewhere, both `namespace` and `podLabels` must be set together (see `_helpers.tpl`'s `headscale.netpol.ingressControllerFrom`).

**Headscale is single-writer.** Network-map recomputation is CPU-bound and not shardable, so `replicaCount` for the headscale Deployment should stay at 1 (there's a warning comment directly above it in `values.yaml`). DERP relays and the UI scale horizontally; headscale and Postgres don't. Don't "fix" this by bumping `replicaCount` or adding an HPA for the API without reading `docs/SCALING.md` first.

**Postgres is bundled but swappable.** `postgresql.enabled: true` (default, in-cluster StatefulSet) vs. `postgresql.external.enabled: true` (managed DB — RDS/Cloud SQL/etc.) are mutually exclusive toggles. `postgresql.config.*` in `values.yaml` renders directly into `postgresql.conf` — add/remove keys there rather than templating new ones.

**Secrets priority (Postgres password): Vault → `external.existingSecret` → `auth.existingSecret` → chart auto-generated Secret.** Vault integration (`vault.enabled`) is opt-in via the Vault Secrets Operator (VSO); it writes a normal K8s Secret that the Deployment consumes via `secretKeyRef` — the Deployment template itself is identical regardless of secret source. Secret rotation is expected to trigger a `rolloutRestart` (see `docs/VAULT.md`).

**Images are built from source in CI**, not pulled from upstream registries. `docker/Dockerfile` clones `juanfont/headscale` at a pinned tag and builds a `distroless/static:nonroot` image (no shell, UID 65532). `docker/ui/Dockerfile` clones `gurucomputing/headscale-ui`, builds with `npm ci --ignore-scripts`, and serves it from `nginx-unprivileged` (UID 101). Both stages run `apk upgrade` in intermediate layers to keep CVE scans clean even though the base images are pinned — don't remove those lines to "simplify" the Dockerfile. Both containers run read-only root filesystems (Compose sets `read_only: true` + tmpfs mounts for the paths that need to be writable; check `docker-compose.yml`'s `x-security-strict` anchor before adding a new writable path).

**CI (`.github/workflows/build-image.yml`)** matrix-builds both images, runs Trivy (CRITICAL+HIGH, `ignore-unfixed: true`, fails the run on findings) before pushing, uploads SARIF to GitHub code scanning, then does a multi-arch build+push to GHCR only after the scan passes. Triggers: manual dispatch, push to `main` touching `docker/**`, and `v*.*.*` tags.

**Placeholders to search-and-replace for a new deployment** (not code to refactor — see README's table for the full list and exact file locations): `eslam-adel92` (GHCR namespace), `hs.example.com` (public FQDN), `admin@example.com` (ACME email), `hs.internal` (MagicDNS base domain), `letsencrypt` (cert-manager ClusterIssuer name).

**`hs-add-device`** auto-detects the running backend in this order: `$HS_BIN` env var → a K8s pod matching `app.kubernetes.io/name=headscale,app.kubernetes.io/component=control-plane` → `docker compose exec` (tried from cwd, then `compose/`, then `../compose/`). It also auto-sources `.env`/`compose/.env`/`../compose/.env` for `HEADSCALE_DOMAIN`. If you add a new detection path, keep the same fallback order and keep it silent-on-success / loud-on-failure (`❌ ...` to stderr, `exit 1`).
