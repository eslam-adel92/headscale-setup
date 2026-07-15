# Vault Integration (Optional)

The chart supports HashiCorp Vault via the **Vault Secrets Operator (VSO)** pattern. When enabled, the PostgreSQL password lives in Vault; VSO syncs it into a Kubernetes Secret which Postgres and Headscale consume via `secretKeyRef`.

## Why VSO (not Vault Agent Injector)?

- **Distroless-friendly**: no shell = we can't run an entrypoint script that reads a rendered file. VSO writes into a real Secret; the app reads it via `secretKeyRef` as if Vault didn't exist.
- **Native Kubernetes primitive**: a rotation in Vault triggers a Secret update → optional `rolloutRestart` — declarative, GitOps-clean.
- **One code path**: whether the password comes from Vault, from you, or from the chart's autogen, the Deployment template is identical.

## Prereqs

Install VSO:
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm upgrade --install vault-secrets-operator hashicorp/vault-secrets-operator \
  --namespace vault-secrets-operator --create-namespace
```

Bootstrap a `VaultConnection` + `VaultAuth` CR (usually by platform team, done once):

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: vault-connection
  namespace: headscale
spec:
  address: https://vault.example.com:8200
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: vault-auth
  namespace: headscale
spec:
  vaultConnectionRef: vault-connection
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: headscale
    serviceAccount: default
```

Vault-side policy for the KV path:
```hcl
path "kv/data/apps/headscale/postgres" {
  capabilities = ["read"]
}
```

## Seed the secret in Vault

```bash
vault kv put kv/apps/headscale/postgres \
  password="$(openssl rand -base64 32)"
```

The field name **must** match `postgresql.auth.existingSecretKey` (default: `password`). If you use a different key, update it in `values.yaml`:

```yaml
postgresql:
  auth:
    existingSecretKey: db_password   # matches your Vault field
```

## Enable in values.yaml

```yaml
vault:
  enabled: true
  connectionRef: vault-connection
  authRef: vault-auth
  mount: kv
  path: apps/headscale/postgres
  refreshAfter: 1h
  destinationSecretName: headscale-vault-db
```

Install:
```bash
helm upgrade --install headscale ./helm/headscale \
  --namespace headscale --create-namespace \
  -f values-prod.yaml
```

## What actually happens

1. Chart creates a `VaultStaticSecret` CR named `<release>-vault-db`.
2. VSO reads `kv/apps/headscale/postgres` from Vault.
3. VSO writes a K8s Secret named `headscale-vault-db` with key `password`.
4. Postgres StatefulSet mounts it as `POSTGRES_PASSWORD`.
5. Headscale Deployment mounts it as `HEADSCALE_DATABASE_POSTGRES_PASSWORD`.
6. Every `refreshAfter` VSO re-fetches; if Vault value changed, VSO updates the Secret and triggers `rolloutRestart` on both workloads.

## Rotation flow

```bash
# 1. Rotate in Vault
vault kv put kv/apps/headscale/postgres password="$(openssl rand -base64 32)"

# 2. Wait for VSO to sync (up to `refreshAfter`) — or force:
kubectl -n headscale annotate vaultstaticsecret <release>-vault-db \
  vso.hashicorp.com/force-sync="$(date +%s)" --overwrite

# 3. VSO auto-rolls the pods. Verify:
kubectl -n headscale rollout status deploy/headscale
kubectl -n headscale rollout status sts/<release>-postgresql
```

## Disable Vault

```yaml
vault:
  enabled: false
```

Chart falls back to `postgresql.auth.existingSecret` or auto-gen (see `DATABASE.md`).

## Not using VSO?

- **Vault Agent Injector**: possible but requires a shim. Ping if you want the pattern.
- **External Secrets Operator (ESO)**: exact same shape as VSO. The chart's template can be adapted to emit an `ExternalSecret` instead of `VaultStaticSecret` in ~5 lines.
- **Manual `kubectl create secret`**: set `vault.enabled: false` and `postgresql.auth.existingSecret: my-manually-created-secret`.

## Threat model note

VSO holds Vault tokens in memory only; the sync destination Secret is a regular K8s Secret (etcd-encrypted if you've enabled that). If a K8s namespace admin can read Secrets in the `headscale` namespace, they can read the DB password — Vault doesn't magic that away. Namespace-level Secret RBAC still matters.
