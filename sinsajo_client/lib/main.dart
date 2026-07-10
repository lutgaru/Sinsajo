import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/transcription_screen.dart';

void main() {
  runApp(const ProviderScope(child: SinsajoApp()));
}

class SinsajoApp extends StatelessWidget {
  const SinsajoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sinsajo Client',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const TranscriptionScreen(),
    );
  }
}
