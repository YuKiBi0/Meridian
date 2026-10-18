# syntax=docker/dockerfile:1

# ---- console ----
FROM node:24-alpine AS console
WORKDIR /src/console
COPY console/package.json console/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY console/ ./
RUN npm run build

# ---- server ----
FROM golang:1.26-alpine AS server
WORKDIR /src/server
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ ./
COPY --from=console /src/console/dist/ ./internal/web/dist/
ARG VERSION=1.1.0
RUN CGO_ENABLED=0 go build -trimpath -tags timetzdata \
      -ldflags "-s -w -X main.version=${VERSION}" \
      -o /out/meridian-server ./cmd/meridian-server

# ---- runtime ----
FROM scratch
COPY --from=server /out/meridian-server /meridian-server
USER 65532:65532
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD ["/meridian-server", "healthcheck"]
ENTRYPOINT ["/meridian-server"]
