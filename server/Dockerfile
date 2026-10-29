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

# Optional transcribe-rs backends: "" (default, ONNX-only),
# "whisper-cpp" (WhisperTinyEn/WhisperSmall) or "whisperfile" (WhisperfileSmall).
# Example: docker build --build-arg FEATURES=whisper-cpp .
ARG FEATURES=""

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/app/target \
    if [ -z "$FEATURES" ]; then cargo build --release; else cargo build --release --features "$FEATURES"; fi \
    && cp /app/target/release/sinsajo-server /app/sinsajo-server

FROM ubuntu:26.04

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libomp5 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/sinsajo-server /app/sinsajo-server

RUN mkdir -p /app/models /app/records

EXPOSE 8765

ENTRYPOINT ["/app/sinsajo-server"]
CMD ["--model", "ParakeetTDT", "--autodownload-model", "--model-dir", "/app/models", "--records-dir", "/app/records"]
