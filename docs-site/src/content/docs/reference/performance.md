---
title: Performance
description: Benchmarks and tuning tips.
---

| Metric | Value |
|--------|-------|
| Latency | ~150–300ms chunk → text |
| CPU | ~20–40% (1 core) |
| RAM | ~500MB (Int8) |
| Accuracy | ~95% clean Spanish |
| Bandwidth | ~256KB/s PCM; VAD reduces ~60% silence |

## Optimizations

- **Quantization** — Int8 is ~2% less accurate than Float32 but ~2× faster
- **VAD** — Saves bandwidth and server CPU by skipping silence
- **Model choice** — `Canary180M` (180M params) faster; `ParakeetTDT` (0.6B) more accurate
- **GPU** — `transcribe-rs` with `OrtAccelerator::Auto` / `Cuda`
- **Chunk size** — Smaller `frameSamples` (256) = lower latency but more overhead

## Measuring

Server logs chunk timing; client shows end-to-end in UI. Test with pre-recorded WAV piped over WebSocket for reproducible benchmarks.
