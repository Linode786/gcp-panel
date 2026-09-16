FROM golang:1.21-alpine AS build
WORKDIR /app
COPY main.go .
RUN go mod init proxy
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o proxy

FROM gcr.io/distroless/static
COPY --from=build /app/proxy /
EXPOSE 8080
ENTRYPOINT ["/proxy"]
