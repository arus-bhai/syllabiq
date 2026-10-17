import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'repositories/syllabus_repository.dart';
import 'screens/splash_screen.dart';
import 'services/api_service.dart';

// TODO: point this at your FastAPI server.
// - Android emulator reaching a server on your host machine: http://10.0.2.2:8000
// - iOS simulator: http://localhost:8000
// - Physical device: your machine's LAN IP, e.g. http://192.168.1.20:8000
const String kApiBaseUrl = 'https://syllabiq-backend.fastapicloud.dev';

void main() {
  // Safety net for uncatchable async errors originating inside package
  // internals (e.g. a known `vad` package race where a trailing audio
  // frame fires after its internal StreamController has closed — see
  // session_screen.dart's stop/restart delay for the primary mitigation).
  // Without this, such an error crashes the entire app instead of just
  // being logged.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught async error (non-fatal, logged): $error');
    return true; // handled — don't crash the app
  };

  runApp(const SyllabusTutorApp());
}

class SyllabusTutorApp extends StatelessWidget {
  const SyllabusTutorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final apiService = ApiService(baseUrl: kApiBaseUrl);
    final repository = SyllabusRepository(apiService: apiService);

    return MaterialApp(
      title: 'Syllabiq',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00C2A8), // teal, per brand palette
          primary: const Color(0xFF00776A),
          surface: const Color(0xFFF7F5F1), // "paper"
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F5F1),
        textTheme: GoogleFonts.spaceGroteskTextTheme(),
        appBarTheme: AppBarTheme(
          titleTextStyle: GoogleFonts.spaceGrotesk(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1C1B19),
          ),
        ),
      ),
      home: SplashScreen(repository: repository),
    );
  }
}