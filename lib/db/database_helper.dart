import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/syllabus.dart';
import '../models/cached_session.dart';

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
      version: 2,
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
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createSessionsTable(db);
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
}
