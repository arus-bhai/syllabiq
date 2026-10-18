/// One recorded question that couldn't be sent to the backend yet — saved
/// to disk so it survives an app restart and gets sent automatically once
/// connectivity returns.
class PendingQuestion {
  PendingQuestion({
    required this.id,
    required this.sessionId,
    required this.wavPath,
    required this.createdAt,
  });

  final int id;
  final String sessionId;

  /// Path to the recorded utterance's WAV file on disk. Stored as a file
  /// rather than a sqlite BLOB — recordings can be a few hundred KB each,
  /// and several may queue up while offline.
  final String wavPath;
  final DateTime createdAt;

  factory PendingQuestion.fromDbMap(Map<String, dynamic> map) {
    return PendingQuestion(
      id: map['id'] as int,
      sessionId: map['session_id'] as String,
      wavPath: map['wav_path'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
