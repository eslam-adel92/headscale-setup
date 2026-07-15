# Web UI — headscale-ui

The chart and Compose stack ship an optional web frontend built from [gurucomputing/headscale-ui](https://github.com/gurucomputing/headscale-ui).

## What you get

- A static Svelte SPA that talks to the headscale API from the user's browser.
- Same subdomain as headscale (`/web` path) — avoids CORS entirely.
- Runs on our own hardened image (`nginx-unprivileged`, non-root UID 101, read-only rootfs).
- Trivy-scanned in CI like every other image.
- No shared secret with headscale — each user authenticates with their own API key.
- Optional Basic Auth as a first hurdle (see [`UI_BASIC_AUTH.md`](UI_BASIC_AUTH.md)).

## URLs

| Where | How to reach |
|---|---|
| Compose | `https://<HEADSCALE_DOMAIN>/web` |
| Kubernetes (Helm) | `https://<ingress.host>/web` |

## Enable / disable

### Compose

The UI is always in the stack. To remove it, delete or comment out the `headscale-ui` service and the `/web*` block in the Caddyfile.

Enable Basic Auth: set `UI_BASIC_AUTH_HASH` in `.env` (see `UI_BASIC_AUTH.md`).

### Helm

One switch:
```yaml
ui:
  enabled: true              # or false
  image:
    repository: ghcr.io/eslam-adel92/headscale-ui
    tag: "2026-03-17"
```

When disabled, the chart skips the UI Deployment, Service, NetworkPolicy, Ingress, and Basic-Auth Secret.

## First sign-in

The UI needs an API key to talk to headscale. Create one and paste it into the UI's **Settings → API key** field:

```bash
# Compose:
docker compose exec headscale headscale apikeys create --expiration 90d

# Kubernetes:
kubectl -n headscale exec deploy/headscale -- headscale apikeys create --expiration 90d
```

The key is stored client-side (browser localStorage). Rotate periodically:

```bash
headscale apikeys expire --prefix <first-few-chars>
headscale apikeys create --expiration 90d
```

## Compatibility

Headscale-ui pins to specific headscale minor versions — check the compatibility matrix in the upstream README before upgrading either component.

Current alignment in this chart:
- headscale `0.29.1`
- headscale-ui `2026-03-17`

## Custom images vs. upstream

We build headscale-ui from source ourselves so we can:

- Pin an exact tag and know what's in the image.
- Ship it on `nginx-unprivileged` (already runs as UID 101, no root ever).
- Serve on a read-only rootfs via `tmpfs` mounts for nginx's writable paths.
- Route it through the same GHCR namespace as headscale, with the same Trivy gate.

If you'd rather use the upstream image, point at it directly:

```yaml
# Helm
ui:
  image:
    repository: ghcr.io/gurucomputing/headscale-ui
    tag: latest

# Compose (.env)
HEADSCALE_UI_IMAGE=ghcr.io/gurucomputing/headscale-ui:latest
```

The upstream image now defaults to ports 8080/8443 (was 80/443 in older tags), which our nginx routing already assumes.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Blank page / CORS errors | UI must live on the same subdomain as the API at `/web`. If you're serving them separately, you'll need CORS shim in the reverse proxy — see the upstream README. |
| "Missing Bearer Prefix" | No API key configured. Create one via `headscale apikeys create` and paste into Settings. |
| 404 on `/web/foo` after refresh | SPA fallback missing — the shipped `nginx.conf` handles this via `try_files … /web/index.html;`. If you replaced the config, add that line back. |
| Ingress serves API on `/web` too | Path ordering — the chart puts `/web` on a separate Ingress resource (`ui-ingress.yaml`) so ingress-nginx sees the more-specific prefix and wins. Check both Ingress resources exist. |
| 401 prompt on API calls | Basic Auth annotations leaked to the API Ingress. Verify they're only on `ui-ingress.yaml`. |
