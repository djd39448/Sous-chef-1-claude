# Multi-stage build for the Sous Chef Go backend.
#
# Target: Linux / arm64 (AWS Graviton, cheaper Fargate). Build a static
# CGO-free binary in the first stage, then copy it into a minimal
# distroless image so the final layer is tiny (~15 MB) and runs as a
# non-root user with no shell.

# ─────────────────────────────────────────────────────────────
# Stage 1 — build the binary
# ─────────────────────────────────────────────────────────────
FROM --platform=linux/arm64 golang:1.26-alpine AS build

WORKDIR /src

# Cache the module download as its own layer.
COPY go.mod go.sum ./
RUN go mod download

# Source. The .dockerignore keeps .env and local cruft out.
COPY . .

# Static binary, no CGO. -ldflags strips debug + symbol tables.
RUN CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
    go build -trimpath -ldflags="-s -w" -o /out/server ./cmd/server

# ─────────────────────────────────────────────────────────────
# Stage 2 — runtime image
# ─────────────────────────────────────────────────────────────
FROM --platform=linux/arm64 gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/server /server

EXPOSE 8080

# The distroless `nonroot` user is UID/GID 65532 — no shell, no package
# manager, smallest blast radius if anything tries to escape.
USER nonroot:nonroot

ENTRYPOINT ["/server"]
