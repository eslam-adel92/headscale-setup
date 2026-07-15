# UI Basic Auth

Adds an HTTP Basic Auth prompt in front of `/web` **without** touching the API path — Tailscale clients keep working unauthenticated (they use pre-auth keys / OIDC).

## Why it lives in front of the UI only

The headscale API is what every `tailscale up` and running client talks to. It has to be reachable without a human present. Basic Auth on `/` would break every device on the tailnet. Basic Auth on `/web` only stops random people from even seeing the login page.

This means Basic Auth is a **first hurdle**, not the real access control — the real gate is the per-user API key you paste into the UI after logging in. Think of it as "keep the login page off the public internet", not user auth.

---

## Kubernetes (Helm)

### Option A — Chart generates the Secret (single user)

Simplest path. The chart uses Sprig's `htpasswd` function to bcrypt-hash the password at render time and creates the ingress-nginx-compatible Secret.

Values (in a `values-prod.yaml` under `.gitignore`):

```yaml
ui:
  basicAuth:
    enabled: true
    realm: "headscale-ui"
    username: "admin"
    password: "PleaseSetMeAtDeployTime"
```

Or pass at deploy time — never commit the password:

```bash
helm upgrade --install headscale ./helm/headscale \
  -f helm/headscale/values.yaml \
  --set ui.basicAuth.enabled=true \
  --set-string ui.basicAuth.password="$(openssl rand -base64 24)"
```

The chart:
1. Emits a `Secret` named `<release>-headscale-ui-auth` with a bcrypt htpasswd entry (`admin:$2a$10$…`).
2. Adds `nginx.ingress.kubernetes.io/auth-*` annotations to the UI-only Ingress (`<release>-headscale-ui`) — the API Ingress is untouched.
3. Adds a `checksum/ui-auth` annotation so nginx reloads when you rotate the password.

### Option B — Bring your own Secret (multi-user)

For teams. Create an htpasswd file locally, then make a Secret:

```bash
htpasswd -Bbc auth alice 'alice-password'
htpasswd -Bb  auth bob   'bob-password'
htpasswd -Bb  auth eve   'eve-password'

kubectl -n headscale create secret generic headscale-ui-multiuser \
  --from-file=auth
```

Then in values:
```yaml
ui:
  basicAuth:
    enabled: true
    existingSecret: headscale-ui-multiuser
```

Chart skips the generated Secret and points the annotations at yours.

### Rotate password (Option A)

Change `ui.basicAuth.password` and `helm upgrade` — the `checksum/ui-auth` annotation forces nginx to reload with the new credentials.

### Disable

```yaml
ui:
  basicAuth:
    enabled: false
```

The `nginx.ingress.kubernetes.io/auth-*` annotations disappear on the next `helm upgrade`; the generated Secret is retained (via `helm.sh/resource-policy: keep`) in case you re-enable later.

---

## Docker Compose

Caddy uses its `basic_auth` directive with bcrypt hashes.

1. Generate the hash:
   ```bash
   ./scripts/hs-hash-ui-password 'yourPassword'
   # or:
   make hash-ui-password PW='yourPassword'
   # → $2a$14$ABC…
   ```

2. Paste it into `compose/.env`:
   ```
   UI_BASIC_AUTH_USER=admin
   UI_BASIC_AUTH_HASH=$2a$14$ABC…   # ← from the previous step
   ```

3. Restart Caddy:
   ```bash
   docker compose up -d caddy
   ```

4. Verify:
   ```bash
   curl -o /dev/null -w '%{http_code}\n' https://<HEADSCALE_DOMAIN>/web
   # → 401
   curl -o /dev/null -w '%{http_code}\n' -u admin:yourPassword https://<HEADSCALE_DOMAIN>/web
   # → 200
   ```

If `UI_BASIC_AUTH_HASH` is empty, Caddy skips Basic Auth entirely — no need to comment out the block. Toggle-friendly for dev vs. prod.

Multiple users in Compose: edit `compose/caddy/Caddyfile` directly and add additional lines under `basic_auth { … }`.

---

## After Basic Auth — the real login

Once past Basic Auth, the UI still needs an API key. Create one:

```bash
# Compose:
docker compose exec headscale headscale apikeys create --expiration 90d

# Kubernetes:
kubectl -n headscale exec deploy/headscale -- headscale apikeys create --expiration 90d
```

Paste it into the UI's **Settings → API key** field. It's stored in localStorage and used for all subsequent API calls.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Prompted for Basic Auth on API calls too | Annotations leaked. The chart puts them only on `ui-ingress.yaml`. Verify `kubectl -n headscale get ingress -o yaml`. |
| Wrong password after rotation | Check the checksum annotation actually changed. If Helm reused the cached Secret, force with `helm upgrade --force`. |
| Caddy returns 500 | Basic Auth requires **bcrypt**. Use `hs-hash-ui-password`. |
| Ingress-nginx returns 503 | The `auth-secret` annotation names a Secret that doesn't exist — `kubectl get secret -n <ns> <release>-headscale-ui-auth`. |
