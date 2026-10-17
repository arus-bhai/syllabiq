class CachedSession {
  final String sessionId;
  final String syllabusId;
  final String syllabusTitle;
  final String cacheName;
  final DateTime createdAt;

  CachedSession({
    required this.sessionId,
    required this.syllabusId,
    required this.syllabusTitle,
    required this.cacheName,
    required this.createdAt,
  });

  static const validity = Duration(hours: 1);

  bool get isExpired => DateTime.now().isAfter(createdAt.add(validity));

  factory CachedSession.fromDbMap(Map<String, dynamic> map) {
    return CachedSession(
      sessionId: map['session_id'] as String,
      syllabusId: map['syllabus_id'] as String,
      syllabusTitle: map['syllabus_title'] as String,
      cacheName: map['cache_name'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toDbMap() {
    return {
      'session_id': sessionId,
      'syllabus_id': syllabusId,
      'syllabus_title': syllabusTitle,
      'cache_name': cacheName,
      'created_at': createdAt.toIso8601String(),
    };
  }
}