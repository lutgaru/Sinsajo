#syntax=docker/dockerfile:1

FROM rust:latest AS builder

RUN apt-get update && apt-get install -y \
    cmake \
    pkg-config \
    libomp5 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/app/target \
    cargo build --release

FROM ubuntu:26.04

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libomp5 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/target/release/sinsajo-server /app/sinsajo-server

RUN mkdir -p /app/models /app/records

EXPOSE 8765

ENTRYPOINT ["/app/sinsajo-server"]
CMD ["--model", "ParakeetTDT", "--autodownload-model", "--model-dir", "/app/models", "--records-dir", "/app/records"]
