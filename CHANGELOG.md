# Changelog

All notable changes to this project. Follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Documentation
- Full README rewrite: added ToC, feature matrix, expanded design decisions,
  common-ops cookbook, and cross-links to every doc.
- New `CHANGELOG.md`.
- Consistency pass across all docs.

## [0.4.0] — Chart with Basic Auth + same-namespace ingress

### Added
- **UI Basic Auth** on ingress. Applied only to the `/web` Ingress via
  `nginx.ingress.kubernetes.io/auth-*` annotations — the API path remains
  anonymous so Tailscale clients keep working.
- `templates/ui-basic-auth-secret.yaml` — chart-generated bcrypt htpasswd
  Secret using Sprig's `htpasswd USER PASS`.
- `templates/ui-ingress.yaml` — separate Ingress for `/web` so auth
  annotations don't affect the API Ingress.
- `scripts/hs-hash-ui-password` — bcrypt hasher for Compose Basic Auth
  (calls `caddy hash-password` locally or via docker; falls back to `htpasswd`).
- `networkPolicy.ingressController.namespace` value. Empty (default) = same
  namespace as release; uses a pod-only selector. Set to a namespace name to
  emit `namespaceSelector + podSelector`.
- `networkPolicy.ingressController.podLabels` value for controllers whose
  labels differ from `app.kubernetes.io/name: ingress-nginx`.
- New docs: `docs/UI_BASIC_AUTH.md`, `docs/WEB_UI.md`.

### Changed
- `templates/ingress.yaml` no longer contains the `/web` path — it's owned by
  `ui-ingress.yaml` now. ingress-nginx merges rules from both Ingresses on
  the same host and honours the more-specific `/web` prefix.
- Compose `caddy/Caddyfile`: `/web/*` route now honours `UI_BASIC_AUTH_HASH`
  env var (empty = auth disabled).

## [0.3.0] — Rebrand to generic naming

### Changed
- Project renamed from `headscale-unifonic` to `headscale-setup`.
- All references to specific orgs, domains, users, timezones replaced with
  generic placeholders: `eslam-adel92`, `hs.example.com`, `admin@example.com`,
  `admin`/`alice`/`bob`, `UTC`, `primary` (DERP region).
- Image labels use a `VENDOR` build arg (default `headscale-setup`).
- CI workflow uses `${{ github.repository_owner }}` for the org so
  `ghcr.io/<org>/headscale{,-ui}` resolves automatically per fork.

## [0.2.0] — Web UI (headscale-ui)

### Added
- **`docker/ui/`** — headscale-ui built from source. Two-stage: `node:22-alpine`
  → `nginx-unprivileged` (~30 MB, UID 101, read-only rootfs, tmpfs for
  writable paths).
- `docker/ui/nginx.conf` — serves `/web` with SPA fallback, `/healthz` endpoint,
  security headers.
- Chart UI templates: `ui-deployment.yaml`, `ui-service.yaml`,
  `ui-networkpolicy.yaml`.
- Chart Ingress routes `/web/*` to the UI on the same host as the API
  (avoids CORS).
- Compose stack now bundles a hardened `headscale-ui` service (was optional
  gurucomputing image before).
- Caddyfile routes `/web/*` to the UI, `/*` to the API.
- CI workflow: **matrix build** for both `headscale` and `headscale-ui` — same
  Trivy gate for both.

## [0.1.0] — Trivy scan gate

### Added
- Two-job CI pipeline:
  1. `build-scan` — build amd64 locally, Trivy CRITICAL/HIGH scan (fails run
     on findings, `ignore-unfixed: true`).
  2. `push` — multi-arch build (amd64 + arm64) + push, gated on scan pass.
- SARIF uploaded to GitHub Security → Code scanning under per-image category.
- SARIF also uploaded as an artifact (30-day retention).
- `workflow_dispatch` toggles: `fail_on_vuln` and `push` for smoke tests.
- Trivy DB pulls authenticate via `GITHUB_TOKEN` to dodge rate limits.

## [0.0.3] — Repo hygiene + CI skeleton

### Added
- Top-level `.gitignore` covering env files, secrets, backups, build
  artifacts, data volumes, IDE/OS dirs.
- `compose/.env.example` with inline guidance and required-field markers.
- `.github/workflows/build-image.yml` — initial single-purpose build & push
  workflow (Trivy added in 0.1.0).

## [0.0.2] — PostgreSQL everywhere + optional Vault

### Added
- Bundled `postgres:16-alpine` StatefulSet in the Helm chart.
- `postgresql-configmap.yaml` — every knob rendered from
  `postgresql.config.*` values (no image rebuild for tuning).
- `postgresql-backup-cronjob.yaml` — `pg_dump --format=custom` daily to a PVC.
- `postgresql-networkpolicy.yaml` — DB locked to headscale + backup pods only.
- Compose: real `postgres` service + `postgres-backup` service under a
  `backup` profile.
- Optional Vault integration via HashiCorp Vault Secrets Operator
  (`vault-secret.yaml` → `VaultStaticSecret`).
- DB password source priority chain:
  Vault → `postgresql.external.existingSecret` → `postgresql.auth.existingSecret`
  → chart auto-generated (retained via `helm.sh/resource-policy: keep`).
- New docs: `docs/DATABASE.md`, `docs/VAULT.md`.

## [0.0.1] — Initial project scaffold

### Added
- `docker/Dockerfile` — headscale built from source on
  `golang:1.24-alpine`, deployed on `gcr.io/distroless/static-debian12:nonroot`
  (~28 MB, UID 65532, no shell, no libc).
- Docker Compose stack with Caddy + Let's Encrypt.
- Helm chart core: Deployment/StatefulSet, Service, Ingress, NetworkPolicy,
  PDB, ServiceMonitor, HPA (disabled by default), RBAC.
- `scripts/hs-add-device` — auto-detects Compose/K8s/binary, generates a
  short-lived pre-auth key, prints tailscale up command + QR + deep-link.
- Client install guide covering Fedora, Ubuntu, Arch, K8s sidecar, macOS,
  Windows, iOS, Android.
- Initial docs: `docs/ARCHITECTURE.md`, `docs/SECURITY.md`, `docs/SCALING.md`.

[Unreleased]: https://github.com/eslam-adel92/headscale-setup/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/eslam-adel92/headscale-setup/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/eslam-adel92/headscale-setup/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/eslam-adel92/headscale-setup/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/eslam-adel92/headscale-setup/compare/v0.0.3...v0.1.0
[0.0.3]: https://github.com/eslam-adel92/headscale-setup/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/eslam-adel92/headscale-setup/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/eslam-adel92/headscale-setup/releases/tag/v0.0.1
