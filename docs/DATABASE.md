# Database Guide — PostgreSQL for Headscale

## Why PostgreSQL over SQLite

| | SQLite | PostgreSQL |
|---|---|---|
| Setup complexity | ✅ Zero | 🟡 One extra pod |
| Backup story | 🟡 File copy w/ WAL checkpoint | ✅ `pg_dump` streaming |
| Rolling upgrades | ❌ Requires downtime | ✅ Zero-downtime headscale rollouts |
| PITR | ❌ | ✅ (with WAL archiving) |
| Ops complexity | ✅ Trivial | 🟡 More knobs |

**Rule of thumb**: SQLite for labs (< 20 devices). PostgreSQL for everything else.

## Image choice

**`postgres:16-alpine`** — official, ~80 MB, non-root (UID 70).

Bumping majors is a single-line change:
```yaml
postgresql:
  image:
    tag: "17-alpine"
```

**Not** using Bitnami (paid-tier migration in Aug 2025) or CNPG/Zalando operators (overkill for a DB this small — headscale's schema is a handful of tables).

## Every knob is a values.yaml key

The `postgresql.conf` file is rendered from `postgresql.config.*`. Add/remove keys freely, no rebuild needed:

```yaml
postgresql:
  config:
    shared_buffers: "512MB"          # ← tune to your workload
    max_connections: "200"
    work_mem: "16MB"
    log_min_duration_statement: "500ms"
    jit: "off"                       # sometimes helps OLTP
```

The `checksum/config` annotation on the StatefulSet triggers a rolling restart when config changes.

## Password sources — pick one

| # | Trigger | Behaviour |
|---|---|---|
| 1 | `vault.enabled: true` | VSO syncs from Vault (see [`VAULT.md`](VAULT.md)) |
| 2 | `postgresql.external.enabled: true` | You bring your own Secret |
| 3 | `postgresql.auth.existingSecret: my-secret` | Uses your pre-created Secret |
| 4 | *(default)* | Chart auto-generates 32-char password on install, retained across upgrades via `helm.sh/resource-policy: keep` |

## Docker Compose

```bash
cd compose
cp .env.example .env
echo "POSTGRES_PASSWORD=$(openssl rand -base64 32)" >> .env

docker compose up -d                        # headscale + postgres + UI + caddy
docker compose --profile backup up -d       # + daily pg_dump loop
```

Tune Postgres by editing `compose/postgres/postgresql.conf` and `docker compose restart postgres`.

## Backups on Kubernetes

CronJob runs `pg_dump --format=custom --compress=6` on `postgresql.backup.schedule` (default: `0 2 * * *` = daily 02:00 UTC) into a dedicated PVC:

```yaml
postgresql:
  backup:
    enabled: true
    schedule: "0 2 * * *"
    retentionDays: 14
    storageClass: ""
    size: 20Gi
```

Grab the latest backup:
```bash
make pg-backup                     # trigger a one-off Job
BP=$(kubectl -n headscale get pod -l app.kubernetes.io/component=backup -o name | tail -1)
kubectl -n headscale cp "$BP":/backups/headscale-<timestamp>.dump ./
```

Compose:
```bash
docker compose --profile backup up -d
docker run --rm -v headscale_postgres-backups:/backups alpine ls -lh /backups
```

## Restore

```bash
make pg-restore FILE=./headscale-20260101T020000Z.dump
```

Under the hood:
```bash
kubectl -n headscale scale deploy/headscale --replicas=0
kubectl -n headscale exec -it headscale-postgresql-0 -- \
  psql -U headscale -d postgres -c \
  "DROP DATABASE headscale; CREATE DATABASE headscale OWNER headscale;"
kubectl -n headscale cp ./dump.dump headscale-postgresql-0:/tmp/restore.dump
kubectl -n headscale exec -it headscale-postgresql-0 -- \
  pg_restore -U headscale -d headscale --clean --if-exists /tmp/restore.dump
kubectl -n headscale scale deploy/headscale --replicas=1
```

## Version upgrades

- **Minor** (16.4 → 16.5): safe drop-in restart.
- **Major** (16 → 17): `pg_upgrade` or dump-and-restore:

```bash
# Dump on 16 → deploy 17 → restore
kubectl -n headscale exec -it <pg-16-pod> -- pg_dumpall -U headscale > all.sql
helm upgrade headscale ./helm/headscale --reuse-values --set postgresql.image.tag=17-alpine
# Wait for pod ready:
kubectl -n headscale exec -i <pg-17-pod> -- psql -U headscale postgres < all.sql
```

Zero-downtime major upgrades on prod need CloudNativePG — but that's a bigger operator move.

## Managed / external Postgres

Point at OCI Autonomous DB, RDS, Cloud SQL, etc.:

```yaml
postgresql:
  enabled: false            # skip bundled instance
  external:
    enabled: true
    host: prod-pg.example.com
    port: 5432
    database: headscale
    username: headscale
    existingSecret: headscale-external-db   # you create this
    existingSecretKey: password
    ssl: require
```

The chart's `wait-for-postgres` init container still runs, so headscale won't crash-loop while the connection warms up.

## Monitoring

- `postgres-exporter` isn't shipped by default to keep the chart minimal — add it as an `extraContainers` sidecar if needed.
- Prometheus metrics via the ServiceMonitor:
  - `pg_stat_database_xact_commit` — commit rate
  - `pg_stat_database_conflicts` — deadlocks
  - `pg_stat_bgwriter_checkpoints_timed` — checkpoint frequency

## Troubleshooting

| Symptom | Fix |
|---|---|
| `FATAL: password authentication failed` | Secret content mismatch — `kubectl get secret <dbSecretName> -o jsonpath='{.data.password}' \| base64 -d` |
| `pq: SSL is not enabled on the server` | Set `postgresql.clientConfig.ssl: disable` (in-cluster) or enable Postgres TLS |
| Backup PVC filling up | Reduce `retentionDays` or grow `backup.size` |
| Slow queries | Raise `shared_buffers`; inspect via `log_min_duration_statement` |
