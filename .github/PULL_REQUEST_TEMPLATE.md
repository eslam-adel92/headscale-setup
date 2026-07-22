## What this changes

<!-- One or two sentences: what and why. -->

## Component(s) touched

- [ ] `docker/` / `docker/ui/` (Dockerfiles)
- [ ] `compose/` (Compose stack)
- [ ] `helm/headscale/` (chart)
- [ ] `scripts/`
- [ ] `docs/` / `README.md`
- [ ] `.github/workflows/`

## Validation

There's no app-level test suite in this repo — check the boxes that apply,
per [`CONTRIBUTING.md`](../CONTRIBUTING.md):

- [ ] `helm lint helm/headscale` (chart changes)
- [ ] `helm template headscale helm/headscale -f helm/headscale/values.yaml` renders as expected (chart changes)
- [ ] `docker compose -f compose/docker-compose.yml config` renders as expected (Compose changes)
- [ ] `bash -n scripts/<script>` (script changes)
- [ ] Ran the script/stack against a real local Compose or cluster deployment (behavioral script/chart changes)
- [ ] `docker build` / `make build` succeeds (Dockerfile changes)

## Anything reviewers should pay extra attention to

<!-- e.g. "this touches the same-namespace NetworkPolicy default" or
     "changes the hs-add-device fallback detection order" -->
