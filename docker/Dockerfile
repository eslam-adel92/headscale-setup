# syntax=docker/dockerfile:1.7
###############################################################################
# Headscale — hardened, minimal, multi-arch image built from source.
# Final image: distroless/static:nonroot (~28 MB, no shell, no libc, UID 65532).
###############################################################################
ARG GO_VERSION=1.26.5
FROM --platform=$BUILDPLATFORM golang:$GO_VERSION-alpine AS builder
ARG HEADSCALE_VERSION=0.29.2
ARG VENDOR=eslam-adel92
ARG TARGETOS
ARG TARGETARCH

RUN apk add --no-cache git ca-certificates tzdata && update-ca-certificates

WORKDIR /src
RUN git clone --depth 1 --branch v${HEADSCALE_VERSION} \
    https://github.com/juanfont/headscale.git .

ENV CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    GOFLAGS="-trimpath -mod=readonly"

RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    go build \
      -ldflags="-s -w -X main.version=${HEADSCALE_VERSION}" \
      -o /out/headscale ./cmd/headscale && \
    /out/headscale version

FROM gcr.io/distroless/static-debian12:nonroot AS runtime
ARG HEADSCALE_VERSION=0.29.2
ARG VENDOR=eslam-adel92

LABEL org.opencontainers.image.title="headscale" \
      org.opencontainers.image.description="Self-hosted Tailscale control server — hardened build" \
      org.opencontainers.image.version="${HEADSCALE_VERSION}" \
      org.opencontainers.image.source="https://github.com/juanfont/headscale" \
      org.opencontainers.image.vendor="${VENDOR}" \
      org.opencontainers.image.licenses="BSD-3-Clause"

COPY --from=builder --chown=nonroot:nonroot /out/headscale /usr/local/bin/headscale
COPY --chown=nonroot:nonroot config/config.yaml /etc/headscale/config.yaml

USER 65532:65532
WORKDIR /var/lib/headscale
EXPOSE 8080 3478/udp 9090 50443

ENTRYPOINT ["/usr/local/bin/headscale"]
CMD ["serve"]
