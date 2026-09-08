FROM golang:1.27-bookworm AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o /companion ./cmd/companion
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/* && useradd --uid 10001 --create-home lantern && mkdir /data && chown lantern:lantern /data
COPY --from=build /companion /usr/local/bin/companion
USER lantern
ENV LANTERN_DATABASE=/data/companion.db
ENTRYPOINT ["/usr/local/bin/companion"]
