---
name: Bug report
about: Something in the Compose stack, Helm chart, images, or scripts isn't working
title: ""
labels: bug
---

## Deployment mode

- [ ] Docker Compose
- [ ] Helm / Kubernetes

## Component

- [ ] `docker/` (headscale image)
- [ ] `docker/ui/` (headscale-ui image)
- [ ] `compose/` (Compose stack / Caddy)
- [ ] `helm/headscale/` (chart)
- [ ] `scripts/hs-add-device` or `scripts/hs-hash-ui-password`
- [ ] Other (describe below)

## Versions

- Headscale image tag:
- Headscale-UI image tag:
- Helm chart version (`helm/headscale/Chart.yaml` `version:`) or Compose (git commit/tag):
- `helm version` / `docker compose version`:
- Kubernetes version (if applicable):

## What happened

<!-- Clear description of the bug. -->

## Expected behavior

<!-- What you expected instead. -->

## Steps to reproduce

1.
2.
3.

## Relevant output

<!-- Paste the output of whichever applies:
     - `helm template headscale helm/headscale -f your-values.yaml`
     - `docker compose -f compose/docker-compose.yml config`
     - `kubectl -n headscale describe pod ...` / `kubectl -n headscale logs ...`
     - `docker compose logs ...`
     Redact secrets/domains you don't want public. -->

```
paste here
```
