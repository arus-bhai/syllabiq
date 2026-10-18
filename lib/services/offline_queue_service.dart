import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/database_helper.dart';
import 'api_service.dart';
import 'response_cache_service.dart';

/// What a successfully-drained queued question produced, handed back to
/// whoever called [OfflineQueueService.drainQueue] so it can update the UI
/// if a session screen happens to be open.
class DrainedAnswer {
  DrainedAnswer({
    required this.syllabusId,
    required this.transcript,
    required this.pcmBytes,
  });

  /// The syllabus the question was asked in, so a screen showing a
  /// different syllabus can ignore this answer.
  final String syllabusId;
  final String transcript;
  final Uint8List pcmBytes;
}

/// Persists recorded questions to disk when the backend can't be reached,
/// and sends them once connectivity returns.
///
/// Each queued item is one recorded utterance (WAV bytes) tied to the
/// session it was asked in. The WAV itself is written to a file (not a
/// sqlite BLOB — recordings can run a few hundred KB each and several may
/// pile up while offline); only the file path is stored in the DB.
class OfflineQueueService {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final ResponseCacheService _responseCache = ResponseCacheService();

  Future<Directory> _queueDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'offline_queue'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Saves a recorded question that couldn't be sent right now. The queue
  /// holds at most ONE question per syllabus: if the connection is down the
  /// user won't keep asking, so a newer question for the same syllabus
  /// replaces the older one (its file and row are deleted first). Questions
  /// queued for other syllabi are left alone.
  Future<void> enqueue(
    String syllabusId,
    String sessionId,
    Uint8List wavBytes,
  ) async {
    for (final old in await _db.getPendingQuestions(syllabusId: syllabusId)) {
      final oldFile = File(old.wavPath);
      if (await oldFile.exists()) await oldFile.delete();
      await _db.deletePendingQuestion(old.id);
    }

    final dir = await _queueDir();
    final fileName = 'q_${DateTime.now().microsecondsSinceEpoch}.wav';
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(wavBytes, flush: true);

    await _db.insertPendingQuestion(
      syllabusId: syllabusId,
      sessionId: sessionId,
      wavPath: file.path,
    );
  }

  /// How many questions are waiting, optionally for one syllabus only.
  Future<int> pendingCount({String? syllabusId}) async =>
      (await _db.getPendingQuestions(syllabusId: syllabusId)).length;

  /// Attempts to send every queued question, oldest first. Stops at the
  /// first failure (connectivity has likely dropped again) and leaves that
  /// item and everything after it queued for the next attempt — one failure
  /// never drops a question that hasn't been sent yet.
  ///
  /// Every successfully sent answer is persisted via [ResponseCacheService]
  /// (so Replay always reflects the latest answer the backend actually
  /// gave, even if no session screen is open to receive [onItemSent]).
  ///
  /// Returns how many questions were sent successfully.
  Future<int> drainQueue(
    ApiService apiService, {
    Future<void> Function(DrainedAnswer answer)? onItemSent,
  }) async {
    final pending = await _db.getPendingQuestions();
    var sentCount = 0;

    for (final item in pending) {
      final file = File(item.wavPath);
      if (!await file.exists()) {
        // The recording file vanished somehow — nothing left to send, so
        // drop the stale row instead of retrying it forever.
        await _db.deletePendingQuestion(item.id);
        continue;
      }

      final Uint8List wavBytes = await file.readAsBytes();

      try {
        final result = await apiService.askQuestionStream(
          item.sessionId,
          wavBytes,
        );
        final bytes = await _collectStream(result.pcmStream);
        result.close();

        await _responseCache.save(
          item.syllabusId,
          item.sessionId,
          result.transcript,
          bytes,
        );
        await _db.deletePendingQuestion(item.id);
        await file.delete();
        sentCount++;

        if (onItemSent != null) {
          await onItemSent(
            DrainedAnswer(
              syllabusId: item.syllabusId,
              transcript: result.transcript,
              pcmBytes: bytes,
            ),
          );
        }
      } catch (e) {
        final unreachable =
            e is! ApiException || e.message.startsWith('Could not reach server');
        if (unreachable) {
          // Still offline — keep it queued and retry on next reconnect.
          break;
        }
        // The server answered but rejected it (e.g. the session's 1-hour
        // Gemini cache expired). Retrying can never succeed, so drop it
        // instead of blocking the queue forever.
        await _db.deletePendingQuestion(item.id);
        await file.delete();
      }
    }

    return sentCount;
  }

  Future<Uint8List> _collectStream(Stream<List<int>> stream) async {
    final builder = BytesBuilder();
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.toBytes();
  }
}
