# syntax=docker/dockerfile:1.7
###############################################################################
# headscale-ui — hardened, minimal, multi-arch image built from source.
# Final: nginxinc/nginx-unprivileged:alpine (~30 MB, UID 101, serves on 8080).
###############################################################################

FROM --platform=$BUILDPLATFORM node:22-alpine AS builder
ARG HEADSCALE_UI_VERSION=2026-03-17
ARG VENDOR=eslam-adel92

RUN apk add --no-cache git ca-certificates && update-ca-certificates
WORKDIR /src
RUN git clone --depth 1 --branch ${HEADSCALE_UI_VERSION} \
    https://github.com/gurucomputing/headscale-ui.git .

ENV NPM_CONFIG_AUDIT=false NPM_CONFIG_FUND=false
RUN --mount=type=cache,target=/root/.npm \
    npm ci --ignore-scripts
RUN npm run build && ls -la build

FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime
ARG HEADSCALE_UI_VERSION=2026-03-17
ARG VENDOR=eslam-adel92

LABEL org.opencontainers.image.title="headscale-ui" \
      org.opencontainers.image.description="Web frontend for headscale — hardened build" \
      org.opencontainers.image.version="${HEADSCALE_UI_VERSION}" \
      org.opencontainers.image.source="https://github.com/gurucomputing/headscale-ui" \
      org.opencontainers.image.vendor="${VENDOR}" \
      org.opencontainers.image.licenses="BSD-3-Clause"

COPY --chown=101:101 nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=101:101 /src/build /usr/share/nginx/html/web

USER 101:101
EXPOSE 8080
STOPSIGNAL SIGQUIT
CMD ["nginx", "-g", "daemon off;"]
