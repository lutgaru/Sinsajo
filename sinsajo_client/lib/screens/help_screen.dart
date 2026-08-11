// lib/screens/help_screen.dart

import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Help'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HelpSection(
            icon: Icons.lightbulb_outline,
            title: 'What is Sinsajo?',
            children: [
              Text(
                'Sinsajo is a client/server app that transcribes your voice '
                'into text in real time. This app is the client: it only '
                'records the microphone and displays the text. The actual '
                'transcription is done by a separate program called the '
                'Sinsajo server.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          _HelpSection(
            icon: Icons.settings_input_antenna,
            title: 'How it works',
            children: [
              const _StepItem(
                number: '1',
                text: 'You speak. The app listens and detects when there is '
                    'speech (Voice Activity Detection).',
              ),
              const _StepItem(
                number: '2',
                text: 'Only your speech is sent over the network to the '
                    'server using a WebSocket connection.',
              ),
              const _StepItem(
                number: '3',
                text: 'The server transcribes the audio with a local AI model '
                    'that runs on the server machine.',
              ),
              const _StepItem(
                number: '4',
                text: 'The text is sent back to the app and appears on screen '
                    'almost instantly.',
              ),
            ],
          ),
          _HelpSection(
            icon: Icons.memory,
            title: 'Why do I need the server?',
            children: [
              Text(
                'The AI models that do the transcription are too large to run '
                'inside this app. They run on a server, usually a PC on the '
                'same Wi-Fi network that stays powered on while you need it.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'If the dot in the top bar is red or grey, it usually means '
                'the server is not installed, not running, or the IP address '
                'in Settings does not point to it.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          _HelpSection(
            icon: Icons.download,
            title: 'Install the server',
            children: [
              Text(
                'The server runs on almost any computer: Windows, Linux or '
                'macOS. You have three options.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              const _MiniTitle('Option 1: Download a ready-made binary'),
              const SizedBox(height: 4),
              Text(
                'Grab the server for your operating system from the releases '
                'page and run it:',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              const _CodeBlock(
                code: 'https://github.com/lutgaru/Sinsajo/releases/latest',
              ),
              const SizedBox(height: 8),
              Text(
                'Download the Windows, Linux or macOS file, then run the '
                'server in a terminal:',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              const _CodeBlock(
                code: './sinsajo-server --model ParakeetTDT --autodownload-model',
              ),
              const SizedBox(height: 16),
              const _MiniTitle('Option 2: Build from source'),
              const SizedBox(height: 4),
              Text(
                'Install Rust from rustup.rs, then open a terminal in the '
                'project folder and run:',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              const _CodeBlock(
                code: 'cd server\n'
                    'cargo run --release -- --model ParakeetTDT --autodownload-model',
              ),
              const SizedBox(height: 16),
              const _MiniTitle('Option 3: Run with Docker'),
              const SizedBox(height: 4),
              Text(
                'On a machine with Docker installed, build the image and run '
                'the container:',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              const _CodeBlock(
                code: 'docker build -t sinsajo-server server\n'
                    'docker run -p 8765:8765 \\\n'
                    '  -v sinsajo-models:/app/models \\\n'
                    '  sinsajo-server',
              ),
              const SizedBox(height: 12),
              Text(
                'On the first start the server downloads a model (~2 GB) '
                'from HuggingFace, then starts listening on port 8765.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          _HelpSection(
            icon: Icons.wifi,
            title: 'Connect this app to the server',
            children: [
              const _StepItem(
                number: '1',
                text: 'Find the server machine IP address on the same Wi-Fi '
                    'network (run "ipconfig" on Windows or "ip a" on '
                    'Linux/macOS).',
              ),
              const _StepItem(
                number: '2',
                text: 'Open Settings (gear icon) and enter that IP in the '
                    '"Server IP" field.',
              ),
              const _StepItem(
                number: '3',
                text: 'Back on the main screen, the dot should turn green '
                    'when the connection succeeds.',
              ),
              const _StepItem(
                number: '4',
                text: 'Tap the microphone and start speaking.',
              ),
            ],
          ),
          _HelpSection(
            icon: Icons.build,
            title: 'Troubleshooting',
            children: [
              const _BulletItem(
                icon: Icons.circle,
                text: 'The dot is red: the client cannot reach the server. '
                    'Check the IP in Settings, make sure the server is running '
                    'and that the firewall allows port 8765.',
              ),
              const _BulletItem(
                icon: Icons.circle,
                text: 'Both devices must be on the same local network so they '
                    'can talk to each other.',
              ),
              const _BulletItem(
                icon: Icons.circle,
                text: 'After editing the server IP in Settings, triggers a '
                    'reconnection automatically on the main screen.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Section card ────────────────────────────────

class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData  icon;
  final String    title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: theme.colorScheme.primary,
            child: Text(
              number,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _MiniTitle extends StatelessWidget {
  const _MiniTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        code,
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _BulletItem extends StatelessWidget {
  const _BulletItem({required this.icon, required this.text});

  final IconData icon;
  final String   text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(icon, size: 10, color: theme.colorScheme.outline),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}