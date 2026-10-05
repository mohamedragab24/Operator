import '../services/r2_worker_service.dart';
class Course {
  final String id;
  final String title;
  final String description;
  final String instructorName;
  final String instructorId;
  final String category;
  final String thumbnailUrl;
  final double price;
  final double rating;
  final int studentsCount;
  final int lessonsCount;
  final String durationLabel;
  final List<String> features;

  Course({
    required this.id,
    required this.title,
    required this.description,
    required this.instructorName,
    required this.instructorId,
    required this.category,
    required this.thumbnailUrl,
    required this.price,
    required this.rating,
    required this.studentsCount,
    required this.lessonsCount,
    required this.durationLabel,
    required this.features,
  });

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  factory Course.fromMap(String id, Map<String, dynamic> map) {
    final rawFeatures = map['features'];

    final features = rawFeatures is List
        ? rawFeatures.map((e) => e.toString()).toList()
        : <String>[];

    return Course(
      id: id,
      title: (map['title'] ?? map['name'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),

      instructorName: (map['instructorName'] ?? map['instructor'] ?? '').toString(),
      instructorId: (map['instructorId'] ?? map['ownerUid'] ?? map['mufhemId'] ?? '').toString(),

      category: (map['category'] ?? '').toString(),

      // يدعم بيانات الموقع الحالية
      thumbnailUrl: R2WorkerService.tokenToUrl(
            (map['thumbnailUrl'] ?? map['coverUrl'] ?? '').toString(),
          ) ??
          (map['thumbnailUrl'] ?? map['coverUrl'] ?? '').toString(),

      price: _toDouble(map['price']),
      rating: _toDouble(map['rating']),

      // الموقع يستخدم totalEnrollments
      studentsCount:
          _toInt(map['studentsCount'] ?? map['totalEnrollments']),

      // يدعم lessonsCount أو يحسب العدد من lessons
      lessonsCount: _toInt(
        map['lessonsCount'] ??
            (map['lessons'] is List
                ? (map['lessons'] as List).length
                : 0),
      ),

      durationLabel:
          (map['durationLabel'] ?? map['duration'] ?? '').toString(),

      features: features,
    );
  }
}
