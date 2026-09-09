---
title: Quick Start
description: Run Sinsajo locally in minutes — server + client.
---

## Prerequisites

- Flutter 3.0+ (client)
- Rust 1.70+ (server) or Docker
- Android device / emulator or modern browser for Web

## 1. Clone

```bash
git clone https://github.com/lutgaru/Sinsajo.git
cd Sinsajo
```

## 2. Start the server

import { Tabs, TabItem } from '@astrojs/starlight/components';

<Tabs>
  <TabItem label="Docker Hub (recommended)">
    ```bash
    docker pull lutgaru/sinsajo-server:latest
    docker run -p 8765:8765 \
      -v sinsajo_models:/app/models \
      -v sinsajo_records:/app/records \
      lutgaru/sinsajo-server:latest

    # With a specific model tag
    docker run -p 8765:8765 lutgaru/sinsajo-server:latest --model Canary180M --autodownload-model
    ```
    Docker Compose:

    ```yaml
    services:
      sinsajo-server:
        image: lutgaru/sinsajo-server:latest
        ports: ["8765:8765"]
        volumes:
          - sinsajo_models:/app/models
          - sinsajo_records:/app/records
        restart: unless-stopped
    volumes:
      sinsajo_models:
      sinsajo_records:
    ```
    ```bash
    docker compose up -d
    ```
  </TabItem>
  <TabItem label="Cargo">
    ```bash
    cd server
    cargo run --release -- --model ParakeetTDT --autodownload-model
    # Server on ws://0.0.0.0:8765
    ```
    CLI args:

    | Arg | Default | Description |
    |-----|---------|-------------|
    | `--model` | prompt | `ParakeetTDT` or `Canary180M` |
    | `--autodownload-model` | false | Auto-download if missing |
    | `--port` | 8765 | WebSocket port |
    | `--model-dir` | ./models | Model storage |
    | `--records-dir` | ./records | WAV/OGG output |
  </TabItem>
</Tabs>

Server auto-downloads the model on first run (~2–3GB). Subsequent starts are ~2–3s.

## 3. Run the client

```bash
cd sinsajo_client
flutter pub get
# Edit lib/providers/transcription_provider.dart
# const String kWsUrl = 'ws://YOUR_SERVER_IP:8765';
flutter run
```

Or use the hosted Web App at `/app/` — set the server IP in Settings.

## 4. Use it

1. Tap the microphone button
2. Speak — VAD shows when speech is detected
3. See real-time transcription
4. Tap stop / clean to end and optionally save WAV/OGG on the server
5. Copy or clear the text

See also: [Architecture](/Sinsajo/guides/architecture/), [Configuration](/Sinsajo/guides/configuration/).
