class Lesson {
  final String id;
  final String courseId;
  final String title;
  final int order;
  final int durationSeconds;
  final bool isPreview;

  /// مسار الفيديو داخل Firebase Storage.
  /// ليس رابط فيديو مباشر.
  final String storagePath;

  /// مفتاح الفيديو في Cloudflare R2 (إن وُجد).
  final String r2Key;

  Lesson({
    required this.id,
    required this.courseId,
    required this.title,
    required this.order,
    required this.durationSeconds,
    required this.isPreview,
    required this.storagePath,
    this.r2Key = '',
  });

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;

    final text = value?.toString().toLowerCase();

    return text == 'true' || text == '1';
  }

  factory Lesson.fromMap(
    String id,
    String courseId,
    Map<String, dynamic> map,
  ) {
    final durationSeconds = map['durationSeconds'] != null
        ? _toInt(map['durationSeconds'])
        : _toInt(map['durationMinutes']) * 60;

    final isPreview = map['isPreview'] != null
        ? _toBool(map['isPreview'])
        : _toBool(map['isFreePreview']);

    return Lesson(
      id: id,
      courseId: courseId,

      title: (map['title'] ?? map['name'] ?? '').toString(),

      order: _toInt(map['order']),

      durationSeconds: durationSeconds,

      isPreview: isPreview,

      // الموقع الجديد يخزن storagePath
      storagePath: (map['storagePath'] ?? '').toString(),
      r2Key: (map['r2Key'] ?? '').toString(),
    );
  }

  String get durationLabel {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
