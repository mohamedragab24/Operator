import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/home_shell.dart';
import 'screens/course_detail_screen.dart';
import 'screens/lesson_player_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/account_security_screen.dart';
import 'screens/meeting_screen.dart';
import 'screens/notifications_tab.dart';
import 'screens/admin_control_center_screen.dart';
import 'screens/verify_email_screen.dart';
import 'screens/group_detail_screen.dart';
import 'screens/group_pdf_screen.dart';
import 'screens/group_video_screen.dart';
import 'screens/group_quiz_screen.dart';
import 'screens/lecture_recordings_screen.dart';
import 'services/firebase_bootstrap.dart';

GoRouter buildRouter() {
  final firebaseBootstrap = FirebaseBootstrap.instance;

  return GoRouter(
    initialLocation: '/',
    refreshListenable: firebaseBootstrap.ready,
    redirect: (context, state) {
      final firebaseReady = firebaseBootstrap.ready.value;
      User? currentUser;
      if (firebaseReady) {
        try {
          currentUser = FirebaseAuth.instance.currentUser;
        } catch (_) {
          // Firebase Auth plugin may still be attaching. Treat the user as
          // signed out for routing and let the login screen retry safely.
          currentUser = null;
        }
      }
      final loggedIn = currentUser != null;
      final loggingInRoutes = ['/login', '/forgot-password', '/', '/verify-email'];

      if (!firebaseReady) {
        // Do not force protected screens while Firebase is still starting.
        // The splash hands off to login quickly instead of hanging forever.
        if (state.matchedLocation == '/') return null;
        if (!loggingInRoutes.contains(state.matchedLocation)) return '/login';
        return null;
      }

      // Email verification is disabled: never force users to the verify screen.
      if (state.matchedLocation == '/verify-email') {
        return loggedIn ? '/home' : '/login';
      }

      if (loggedIn && ['/login', '/forgot-password', '/'].contains(state.matchedLocation)) {
        return '/home';
      }

      if (!loggedIn && !loggingInRoutes.contains(state.matchedLocation)) {
        return '/login';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/forgot-password', builder: (context, state) => const ForgotPasswordScreen()),
      GoRoute(path: '/verify-email', builder: (context, state) => const VerifyEmailScreen()),
      GoRoute(path: '/home', builder: (context, state) => const HomeShell()),
      GoRoute(
        path: '/course/:courseId',
        builder: (context, state) => CourseDetailScreen(
          courseId: state.pathParameters['courseId']!,
          initialLessonNumber: int.tryParse(state.uri.queryParameters['lesson'] ?? '') ?? 1,
        ),
      ),
      GoRoute(path: '/notifications', builder: (context, state) => const NotificationsTab()),
      GoRoute(path: '/admin', builder: (context, state) => const AdminDashboardScreen()),
      GoRoute(path: '/admin-control', builder: (context, state) => const AdminControlCenterScreen()),
      GoRoute(path: '/meeting/:requestId', builder: (context, state) => MeetingScreen(requestId: state.pathParameters['requestId']!)),
      // المجموعات: كل المحتوى والاجتماعات تُفتح داخل التطبيق
      GoRoute(path: '/group/:gid', builder: (context, state) => GroupDetailScreen(groupId: state.pathParameters['gid']!)),
      GoRoute(path: '/group/:gid/session/:sid', builder: (context, state) => GroupSessionScreen(groupId: state.pathParameters['gid']!, sessionId: state.pathParameters['sid']!)),
      GoRoute(path: '/group/:gid/pdf/:fid', builder: (context, state) => GroupPdfScreen(groupId: state.pathParameters['gid']!, fileId: state.pathParameters['fid']!, title: state.uri.queryParameters['title'] ?? 'ملف PDF')),
      GoRoute(path: '/group/:gid/video/:vid', builder: (context, state) => GroupVideoScreen(groupId: state.pathParameters['gid']!, kind: state.uri.queryParameters['kind'] ?? 'videos', itemId: state.pathParameters['vid']!, title: state.uri.queryParameters['title'] ?? 'فيديو')),
      GoRoute(path: '/group/:gid/quiz/:qid', builder: (context, state) => GroupQuizScreen(groupId: state.pathParameters['gid']!, quizId: state.pathParameters['qid']!)),
      GoRoute(path: '/admin/recordings', builder: (context, state) => const LectureRecordingsScreen()),
      GoRoute(path: '/admin/recordings/:rid', builder: (context, state) => AdminRecordingPlayerScreen(recordingId: state.pathParameters['rid']!, title: state.uri.queryParameters['title'] ?? 'تسجيل')),
      GoRoute(path: '/change-password', builder: (context, state) => const ChangePasswordScreen()),
      GoRoute(path: '/account-security', builder: (context, state) => const AccountSecurityScreen()),
      GoRoute(
        path: '/course/:courseId/lesson/:lessonId',
        builder: (context, state) => LessonPlayerScreen(
          courseId: state.pathParameters['courseId']!,
          lessonId: state.pathParameters['lessonId']!,
        ),
      ),
    ],
  );
}
