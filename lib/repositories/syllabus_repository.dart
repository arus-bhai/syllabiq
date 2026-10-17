import '../db/database_helper.dart';
import '../models/syllabus.dart';
import '../services/api_service.dart';
import '../models/cached_session.dart';

class SyllabusLoadResult {
  SyllabusLoadResult({required this.syllabi, required this.fromCache});
  final List<Syllabus> syllabi;
  final bool fromCache;
}

class SyllabusRepository {
  SyllabusRepository({required this.apiService});

  final ApiService apiService;
  final DatabaseHelper _db = DatabaseHelper.instance;

  /// Tries the network first and refreshes the local cache on success.
  /// Falls back to whatever is cached locally if the network call fails.
  /// Rethrows only if there's no cache to fall back to either.
  Future<SyllabusLoadResult> loadSyllabi() async {
    try {
      final syllabi = await apiService.fetchSyllabi();
      await _db.upsertSyllabi(syllabi);
      return SyllabusLoadResult(syllabi: syllabi, fromCache: false);
    } catch (e) {
      final cached = await _db.getCachedSyllabi();
      if (cached.isNotEmpty) {
        return SyllabusLoadResult(syllabi: cached, fromCache: true);
      }
      rethrow;
    }
  }

  Future<CachedSession> getOrCreateSession(Syllabus syllabus) async {
    final cached = await _db.getSessionForSyllabus(syllabus.id);
    if (cached != null && !cached.isExpired) {
      return cached;
    }

    final result = await apiService.initSession(syllabus.id);
    final session = CachedSession(
      sessionId: result.sessionId,
      syllabusId: syllabus.id,
      syllabusTitle: result.syllabusTitle,
      cacheName: result.cacheName,
      createdAt: DateTime.now(),
    );
    await _db.saveSession(session);
    return session;
  }
}
