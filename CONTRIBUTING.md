# Contributing

This repo is deployment tooling (Dockerfiles, Compose stack, Helm chart,
onboarding scripts) around upstream [headscale](https://github.com/juanfont/headscale)
and [headscale-ui](https://github.com/gurucomputing/headscale-ui) — not an
application with its own source code. There's no app-level test suite;
"correctness" here means valid Helm/Compose manifests, images that build and
pass the Trivy gate, and scripts that behave under `set -euo pipefail`.

## Before opening a PR

1. Fork the repo and branch from `main`.
2. Run whichever of these apply to your change (also enforced by
   `.github/workflows/validate.yml` on the PR itself):

   ```bash
   make helm-lint                                    # chart changes
   make helm-template                                # chart changes
   docker compose -f compose/docker-compose.yml config   # Compose changes
   bash -n scripts/hs-add-device                     # script changes
   bash -n scripts/hs-hash-ui-password                # script changes
   make build                                        # Dockerfile changes
   make scan                                         # Dockerfile changes
   ```

3. For `scripts/hs-add-device` or `scripts/hs-hash-ui-password`: `bash -n`
   only checks syntax. If you change flag parsing or the Compose/K8s
   auto-detection logic, run the script against a real local Compose stack
   or a real cluster before opening the PR — there's no automated test for
   this behavior.
4. For Helm chart changes, prefer adding/adjusting a `values.yaml` default
   (off by default) over a behavior change that affects existing users
   silently. `helm/headscale/templates/tests/test-connection.yaml` runs on
   `helm test` — extend it if you add a new user-facing endpoint.

## PR scope

Keep PRs focused on one component (image, chart, Compose, script, or docs).
Use the PR template's checklist to show what you validated.

## Reporting security issues

See [`SECURITY.md`](SECURITY.md) — please don't open a public issue for
vulnerabilities.
