FROM golang:1.27.1-alpine AS build
ENV GOTOOLCHAIN=local
WORKDIR /src
COPY go.mod ./
COPY cmd ./cmd
COPY internal ./internal
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/revtrack-api ./cmd/server
RUN mkdir -p /data && chown 65532:65532 /data

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=build /out/revtrack-api /app/revtrack-api
COPY --from=build --chown=65532:65532 /data /data
ENV HOST=0.0.0.0
ENV PORT=8080
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/app/revtrack-api"]
