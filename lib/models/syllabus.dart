class Syllabus {
  final String id;
  final String title;
  final String subject;
  final String grade;
  final DateTime uploadedAt;

  Syllabus({
    required this.id,
    required this.title,
    required this.subject,
    required this.grade,
    required this.uploadedAt,
  });

  /// From GET /api/admin/syllabi response items.
  factory Syllabus.fromApiJson(Map<String, dynamic> json) {
    return Syllabus(
      id: json['id'] as String,
      title: json['title'] as String,
      subject: json['subject'] as String,
      grade: json['grade'] as String,
      uploadedAt: DateTime.parse(json['uploaded_at'] as String),
    );
  }

  /// From a local sqlite row.
  factory Syllabus.fromDbMap(Map<String, dynamic> map) {
    return Syllabus(
      id: map['id'] as String,
      title: map['title'] as String,
      subject: map['subject'] as String,
      grade: map['grade'] as String,
      uploadedAt: DateTime.parse(map['uploaded_at'] as String),
    );
  }

  Map<String, dynamic> toDbMap() {
    return {
      'id': id,
      'title': title,
      'subject': subject,
      'grade': grade,
      'uploaded_at': uploadedAt.toIso8601String(),
    };
  }
}
