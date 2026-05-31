# ─── Build stage ─────────────────────────────────────────────────────────
FROM golang:1.22-alpine AS build

# gcc/musl-dev are needed because we build with CGO enabled (see below).
RUN apk add --no-cache build-base

WORKDIR /src

# Download dependencies first (cached unless go.mod/go.sum change).
COPY go.mod go.sum ./
RUN go mod download

# Build with CGO so the binary can use the C library resolver (getaddrinfo).
# This avoids Go's pure-Go DNS resolver, which fails to resolve Docker Compose
# service names against Docker's embedded DNS (127.0.0.11) on some hosts (notably
# WSL2), reporting "lookup db on 127.0.0.11:53: server misbehaving".
COPY . .
RUN CGO_ENABLED=1 GOOS=linux go build -ldflags="-s -w" -o /out/kms-api .

# ─── Runtime stage ───────────────────────────────────────────────────────
FROM alpine:3.20

RUN apk add --no-cache ca-certificates wget \
    && adduser -D -u 10001 app
USER app

COPY --from=build /out/kms-api /usr/local/bin/kms-api

# Force the cgo/getaddrinfo resolver at runtime. Alpine has no /etc/nsswitch.conf,
# so without this Go would silently fall back to its pure-Go resolver even though
# the binary was built with CGO.
ENV GODEBUG=netdns=cgo

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=5 \
    CMD wget -qO- http://localhost:8080/api/health || exit 1

ENTRYPOINT ["kms-api"]
