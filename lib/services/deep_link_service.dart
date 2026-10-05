import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:go_router/go_router.dart';

/// Handles links like https://YOURDOMAIN.com/course/123 (or the app's own
/// custom scheme masar://course/123 as a fallback).
///
/// Setup required outside this file (cannot be done from Dart alone):
///  Android — add an <intent-filter> with autoVerify="true" in
///    android/app/src/main/AndroidManifest.xml for your https domain, and
///    host a Digital Asset Links file at
///    https://YOURDOMAIN.com/.well-known/assetlinks.json
///  iOS — enable "Associated Domains" capability with
///    applinks:YOURDOMAIN.com in ios/Runner/Runner.entitlements, and host
///    https://YOURDOMAIN.com/.well-known/apple-app-site-association
class DeepLinkService {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  void init(GoRouter router) {
    // Handle the link that launched the app (cold start).
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handle(uri, router);
    });

    // Handle links received while the app is already running.
    _sub = _appLinks.uriLinkStream.listen((uri) => _handle(uri, router));
  }

  void _handle(Uri uri, GoRouter router) {
    // دعم الروابط المخصصة: fahmny://course2-COURSE_ID
    final host = uri.host;
    // Stable app-owned links do not depend on a Vercel/website domain.
    // Examples: fahmny://course/COURSE_ID or fahmny://course2-COURSE_ID
    if (uri.scheme.toLowerCase() == 'fahmny' && host.toLowerCase() == 'course' && uri.pathSegments.isNotEmpty) {
      router.go('/course/${uri.pathSegments.first}');
      return;
    }
    final customCourseMatch = RegExp(r'^course(\d+)-(.+)$', caseSensitive: false).firstMatch(host);
    if (customCourseMatch != null) {
      final lessonNumber = int.tryParse(customCourseMatch.group(1)!) ?? 1;
      final courseId = 'course-${customCourseMatch.group(2)!}';
      router.go('/course/$courseId?lesson=$lessonNumber');
      return;
    }

    final segments = uri.pathSegments;
    final meetingIdx = segments.indexWhere((s) => s == 'meeting' || s == 'meetings');
    if (meetingIdx != -1 && meetingIdx + 1 < segments.length) {
      router.push('/meeting/${segments[meetingIdx + 1]}');
      return;
    }

    // دعم https://DOMAIN/courses/course2-COURSE_ID و https://DOMAIN/course2-COURSE_ID
    for (final segment in segments) {
      final match = RegExp(r'^course(\d+)-(.+)$', caseSensitive: false).firstMatch(segment);
      if (match != null) {
        final lessonNumber = int.tryParse(match.group(1)!) ?? 1;
        final courseId = 'course-${match.group(2)!}';
        router.go('/course/$courseId?lesson=$lessonNumber');
        return;
      }
    }

    final idx = segments.indexWhere((s) => s == 'course' || s == 'courses');
    if (idx != -1 && idx + 1 < segments.length) {
      final courseId = segments[idx + 1];
      router.go('/course/$courseId');
    }
  }

  void dispose() {
    _sub?.cancel();
  }
}
