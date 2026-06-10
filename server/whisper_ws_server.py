"""
whisper_ws_server.py
────────────────────
Wrapper WebSocket → whisper-server.exe (llama.cpp / whisper.cpp style)

Arquitectura:
  Flutter client  ──WS──►  este server (puerto 8765)
                            └─► whisper-server.exe  (HTTP/WS local, ej. puerto 8080)

Dependencias:
    pip install websockets httpx numpy scipy
"""

import asyncio
import json
import logging
import struct
import wave
import io
import time
from pathlib import Path

import httpx
import numpy as np
import websockets
from websockets.server import WebSocketServerProtocol

# ──────────────────────────────────────────────
# CONFIG
# ──────────────────────────────────────────────
WRAPPER_HOST = "0.0.0.0"
WRAPPER_PORT = 8765

# whisper-server.exe endpoint (ajusta según tu binario)
# whisper.cpp server expone  POST /inference  con multipart/form-data
WHISPER_SERVER_URL = "http://127.0.0.1:8080/inference"

SAMPLE_RATE = 16000          # Hz esperado por Whisper
CHANNELS    = 1
SAMPLE_WIDTH = 2             # bytes (int16)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
log = logging.getLogger("whisper-wrapper")


# ──────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────

def pcm_to_wav_bytes(pcm_bytes: bytes) -> bytes:
    """Convierte raw PCM int16 a WAV en memoria."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(SAMPLE_WIDTH)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(pcm_bytes)
    return buf.getvalue()


async def transcribe_chunk(pcm_bytes: bytes) -> str:
    """
    Envía un chunk PCM al whisper-server.exe via HTTP multipart.
    Retorna el texto transcrito.
    """
    wav_bytes = pcm_to_wav_bytes(pcm_bytes)

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            WHISPER_SERVER_URL,
            files={"file": ("audio.wav", wav_bytes, "audio/wav")},
            data={
                "temperature": "0.0",
                "response_format": "json",
            },
        )
        response.raise_for_status()
        result = response.json()

    # whisper.cpp server devuelve {"text": "..."}
    return result.get("text", "").strip()


# ──────────────────────────────────────────────
# PROTOCOLO WebSocket con el cliente Flutter
# ──────────────────────────────────────────────
#
# Mensajes cliente → servidor:
#   { "type": "start", "sample_rate": 16000 }
#   { "type": "audio_chunk" }  + binary frame con PCM int16
#   { "type": "stop" }
#
# Mensajes servidor → cliente:
#   { "type": "partial",  "text": "..." }
#   { "type": "final",    "text": "..." }
#   { "type": "error",    "message": "..." }
#   { "type": "status",   "message": "..." }
# ──────────────────────────────────────────────

class TranscriptionSession:
    def __init__(self, ws: WebSocketServerProtocol):
        self.ws = ws
        self.buffer = bytearray()
        self.running = False

    async def send(self, payload: dict):
        await self.ws.send(json.dumps(payload))

    async def handle_audio_binary(self, data: bytes):
        """Acumula audio y lo procesa en cuanto llega un chunk completo."""
        self.buffer.extend(data)

        # Transcribir cada vez que tengamos ≥ N segundos de audio
        min_chunk_samples = SAMPLE_RATE * 1          # 1 segundo mínimo
        min_chunk_bytes   = min_chunk_samples * SAMPLE_WIDTH

        if len(self.buffer) >= min_chunk_bytes:
            chunk = bytes(self.buffer)
            self.buffer.clear()

            try:
                text = await transcribe_chunk(chunk)
                if text:
                    await self.send({"type": "partial", "text": text})
                    log.info(f"Partial: {text[:60]}...")
            except Exception as e:
                log.error(f"Transcription error: {e}")
                await self.send({"type": "error", "message": str(e)})

    async def flush_remaining(self):
        """Al detener, procesa el audio restante en el buffer."""
        if len(self.buffer) > 0:
            try:
                text = await transcribe_chunk(bytes(self.buffer))
                self.buffer.clear()
                if text:
                    await self.send({"type": "final", "text": text})
            except Exception as e:
                await self.send({"type": "error", "message": str(e)})


async def session_handler(ws: WebSocketServerProtocol):
    """Maneja una conexión WebSocket completa."""
    client_addr = ws.remote_address
    log.info(f"Client connected: {client_addr}")
    session = TranscriptionSession(ws)

    try:
        async for message in ws:
            # ── Mensaje binario → audio PCM ──────────────────
            if isinstance(message, bytes):
                if session.running:
                    await session.handle_audio_binary(message)
                continue

            # ── Mensaje texto → control JSON ─────────────────
            try:
                msg = json.loads(message)
            except json.JSONDecodeError:
                await session.send({"type": "error", "message": "Invalid JSON"})
                continue

            msg_type = msg.get("type")

            if msg_type == "start":
                session.running = True
                session.buffer.clear()
                log.info(f"Session started (sr={msg.get('sample_rate', SAMPLE_RATE)})")
                await session.send({"type": "status", "message": "ready"})

            elif msg_type == "stop":
                session.running = False
                await session.flush_remaining()
                await session.send({"type": "status", "message": "stopped"})
                log.info("Session stopped by client")

            elif msg_type == "ping":
                await session.send({"type": "pong"})

    except websockets.exceptions.ConnectionClosedOK:
        log.info(f"Client disconnected cleanly: {client_addr}")
    except websockets.exceptions.ConnectionClosedError as e:
        log.warning(f"Client disconnected with error: {e}")
    except Exception as e:
        log.exception(f"Unexpected error: {e}")
    finally:
        log.info(f"Session ended: {client_addr}")


# ──────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────

async def main():
    log.info(f"Starting Whisper WebSocket Wrapper on ws://{WRAPPER_HOST}:{WRAPPER_PORT}")
    log.info(f"Forwarding to whisper-server at {WHISPER_SERVER_URL}")

    async with websockets.serve(
        session_handler,
        WRAPPER_HOST,
        WRAPPER_PORT,
        max_size=10 * 1024 * 1024,   # 10 MB por mensaje
        ping_interval=20,
        ping_timeout=10,
    ):
        log.info("Server ready. Waiting for connections...")
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    asyncio.run(main())
