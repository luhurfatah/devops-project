# =============================================================================
# Stage 1: Build
# =============================================================================
FROM golang:1.25-alpine3.20 AS build

# Required for CGO (needed for cgo DNS resolver with Docker Compose)
RUN apk add --no-cache --update build-base

WORKDIR /src

# Cache module downloads independently of source changes
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download -x

COPY . .

# Build with CGO enabled; strip debug symbols for smaller binary
RUN CGO_ENABLED=1 \
    GOOS=linux \
    GOARCH=amd64 \
    go build \
        -ldflags="-s -w -buildid=" \
        -trimpath \
        -o /out/kms-api .

# =============================================================================
# Stage 2: Runtime (distroless static)
# =============================================================================
FROM gcr.io/distroless/static-debian12:nonroot AS runtime

# OCI annotations
LABEL org.opencontainers.image.title="KMS API"
LABEL org.opencontainers.image.description="Key Management System API backend"
LABEL org.opencontainers.image.source="https://github.com/your-org/your-repo"
LABEL org.opencontainers.image.licenses="MIT"

# Copy only the compiled binary from the build stage
COPY --from=build --link /out/kms-api /usr/local/bin/kms-api

# Force cgo resolver at runtime (Alpine-based distroless has no /etc/nsswitch.conf)
ENV GODEBUG=netdns=cgo

# Explicit non-root user (distroless nonroot image already runs as nonroot)
USER nonroot

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=5 \
    CMD ["kms-api", "health"]

ENTRYPOINT ["kms-api"]
