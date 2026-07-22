# Security Policy

This file covers **reporting a vulnerability in this repo's deployment
tooling** (Dockerfiles, Compose stack, Helm chart, onboarding scripts). For
the threat model and control mapping of the resulting deployment, see
[`docs/SECURITY.md`](docs/SECURITY.md).

## Scope

In scope:
- `docker/`, `compose/`, `helm/`, `k8s/`, `scripts/` in this repository.

Out of scope (report upstream instead):
- Headscale itself: <https://github.com/juanfont/headscale/security>
- Headscale-UI itself: <https://github.com/gurucomputing/headscale-ui>

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Instead, use [GitHub Security Advisories](../../security/advisories/new) for
this repository ("Security" tab → "Report a vulnerability"), or email the
maintainer directly if that's unavailable to you. Include:

- Affected component (image, chart template, Compose file, script) and
  version/tag.
- Steps to reproduce, or a minimal `values.yaml` / `.env` that triggers it.
- Impact (what an attacker could do as a result).

## Response

This is a personal/community project without a formal SLA. Expect an initial
response within a few days. Fixes will be released as a new tag and called
out in [`CHANGELOG.md`](CHANGELOG.md).
