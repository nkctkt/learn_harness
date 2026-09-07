# syntax=docker/dockerfile:1.7
# ---- build: 静的リンクのバイナリを作る ----
FROM golang:1.27-alpine AS build
WORKDIR /src
COPY go.mod go.sum* ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/shortener ./cmd/shortener

# ---- runtime: distroless static(シェル無し、パッケージマネージャ無し、非 root)----
# Go の静的バイナリはこれで足りる。OS パッケージが無いので trivy image の対象がほぼバイナリだけになる。
FROM gcr.io/distroless/static-debian12:nonroot AS runtime
COPY --from=build /out/shortener /shortener
USER 65532
EXPOSE 8081
ENTRYPOINT ["/shortener"]
