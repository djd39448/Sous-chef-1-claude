# Multi-stage build for the Sous Chef Go backend.
#
# Builds for whatever architecture the runtime is — Railway runs on
# amd64, an Apple-silicon dev box would build arm64. Buildx sets
# TARGETOS / TARGETARCH automatically; the local `docker build` falls
# back to the build host. Final image is distroless static (~15 MB),
# runs as non-root.
#
# Earlier revisions hard-pinned `--platform=linux/arm64` for an
# AWS Graviton plan; we pivoted to Railway (see CHANGE_LOG.md) and
# this Dockerfile is now portable.

# ─────────────────────────────────────────────────────────────
# Stage 1 — build the binary
# ─────────────────────────────────────────────────────────────
FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS build

ARG TARGETOS=linux
ARG TARGETARCH=amd64

WORKDIR /src

# Cache the module download as its own layer.
COPY go.mod go.sum ./
RUN go mod download

# Source. The .dockerignore keeps .env and local cruft out.
COPY . .

# Static binary, no CGO. -ldflags strips debug + symbol tables.
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags="-s -w" -o /out/server ./cmd/server

# ─────────────────────────────────────────────────────────────
# Stage 2 — runtime image
# ─────────────────────────────────────────────────────────────
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/server /server

EXPOSE 8080

# The distroless `nonroot` user is UID/GID 65532 — no shell, no package
# manager, smallest blast radius if anything tries to escape.
USER nonroot:nonroot

ENTRYPOINT ["/server"]
