import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/database_helper.dart';

/// The most recent answer, as actually persisted to disk — survives app
/// restarts, unlike the in-memory `_lastResponsePcm` it backs.
class CachedResponse {
  CachedResponse({
    required this.sessionId,
    required this.transcript,
    required this.pcmBytes,
    required this.createdAt,
  });

  final String sessionId;
  final String transcript;
  final Uint8List pcmBytes;
  final DateTime createdAt;
}

/// Persists the most recent spoken answer (transcript + raw PCM audio) to
/// disk, so "Replay last response" keeps working after an app restart and
/// with no network at all — not just within one still-open session.
///
/// Only ever the single latest answer is kept — same scope as the
/// in-memory `_lastResponsePcm` field it backs in the session screen. This
/// is durable replay, not a history.
class ResponseCacheService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<File> _pcmFile() async {
    final base = await getApplicationSupportDirectory();
    return File(p.join(base.path, 'last_response.pcm'));
  }

  /// Overwrites whatever was cached before with this answer.
  Future<void> save(
    String sessionId,
    String transcript,
    Uint8List pcmBytes,
  ) async {
    final file = await _pcmFile();
    await file.writeAsBytes(pcmBytes, flush: true);
    await _db.saveLastResponse(
      sessionId: sessionId,
      transcript: transcript,
      pcmPath: file.path,
    );
  }

  /// Returns null if nothing has ever been cached, or if the cached file
  /// has gone missing from disk for some reason.
  Future<CachedResponse?> load() async {
    final row = await _db.getLastResponse();
    if (row == null) return null;

    final file = File(row['pcm_path'] as String);
    if (!await file.exists()) return null;

    return CachedResponse(
      sessionId: row['session_id'] as String,
      transcript: row['transcript'] as String,
      pcmBytes: await file.readAsBytes(),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
