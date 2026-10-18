import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/syllabus.dart';
import '../models/cached_session.dart';
import '../models/pending_question.dart';

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'syllabus_tutor.db');

    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
        CREATE TABLE syllabi (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          subject TEXT NOT NULL,
          grade TEXT NOT NULL,
          uploaded_at TEXT NOT NULL
        )
      ''');
        await _createSessionsTable(db);
        await _createOfflineTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createSessionsTable(db);
        }
        if (oldVersion < 3) {
          await _createOfflineTables(db);
        }
      },
    );
  }

  Future<void> _createSessionsTable(Database db) async {
    await db.execute('''
    CREATE TABLE sessions (
      syllabus_id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL,
      syllabus_title TEXT NOT NULL,
      cache_name TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
  }

  /// `pending_questions` queues recorded questions that couldn't reach the
  /// backend (offline / unreachable) — drained and sent once connectivity
  /// returns. `last_response` is a single-row table (id is always 1) that
  /// durably caches the most recent spoken answer, so "Replay last
  /// response" survives an app restart and works fully offline.
  Future<void> _createOfflineTables(Database db) async {
    await db.execute('''
    CREATE TABLE pending_questions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      wav_path TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
    await db.execute('''
    CREATE TABLE last_response (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      session_id TEXT NOT NULL,
      transcript TEXT NOT NULL,
      pcm_path TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
  }

  // ---------------------------------------------------------------------
  // Sessions (unchanged)
  // ---------------------------------------------------------------------

  // One valid session per syllabus at a time — new init replaces the old row.
  Future<void> saveSession(CachedSession session) async {
    final db = await database;
    await db.insert(
      'sessions',
      session.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<CachedSession?> getSessionForSyllabus(String syllabusId) async {
    final db = await database;
    final rows = await db.query(
      'sessions',
      where: 'syllabus_id = ?',
      whereArgs: [syllabusId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CachedSession.fromDbMap(rows.first);
  }

  Future<void> deleteSessionForSyllabus(String syllabusId) async {
    final db = await database;
    await db.delete('sessions', where: 'syllabus_id = ?', whereArgs: [syllabusId]);
  }

  // ---------------------------------------------------------------------
  // Syllabi (unchanged)
  // ---------------------------------------------------------------------

  /// Replaces the local cache with the given list (insert-or-update per row;
  /// stale rows from a previous fetch are NOT auto-deleted here, since the
  /// admin list is expected to only grow — call clearSyllabi() first if you
  /// ever need a hard resync).
  Future<void> upsertSyllabi(List<Syllabus> syllabi) async {
    final db = await database;
    final batch = db.batch();
    for (final s in syllabi) {
      batch.insert(
        'syllabi',
        s.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Syllabus>> getCachedSyllabi() async {
    final db = await database;
    final rows = await db.query('syllabi', orderBy: 'uploaded_at DESC');
    return rows.map(Syllabus.fromDbMap).toList();
  }

  Future<void> clearSyllabi() async {
    final db = await database;
    await db.delete('syllabi');
  }

  // ---------------------------------------------------------------------
  // Offline question queue
  // ---------------------------------------------------------------------

  Future<void> insertPendingQuestion({
    required String sessionId,
    required String wavPath,
  }) async {
    final db = await database;
    await db.insert('pending_questions', {
      'session_id': sessionId,
      'wav_path': wavPath,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Oldest first, so queued questions are sent in the order they were asked.
  Future<List<PendingQuestion>> getPendingQuestions() async {
    final db = await database;
    final rows = await db.query('pending_questions', orderBy: 'created_at ASC');
    return rows.map(PendingQuestion.fromDbMap).toList();
  }

  Future<void> deletePendingQuestion(int id) async {
    final db = await database;
    await db.delete('pending_questions', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------
  // Last-response cache (single row, id = 1)
  // ---------------------------------------------------------------------

  Future<void> saveLastResponse({
    required String sessionId,
    required String transcript,
    required String pcmPath,
  }) async {
    final db = await database;
    await db.insert(
      'last_response',
      {
        'id': 1,
        'session_id': sessionId,
        'transcript': transcript,
        'pcm_path': pcmPath,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getLastResponse() async {
    final db = await database;
    final rows = await db.query('last_response', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return null;
    return rows.first;
  }
}
