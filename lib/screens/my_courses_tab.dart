import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/course.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class MyCoursesTab extends StatelessWidget {
  const MyCoursesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('يجب تسجيل الدخول أولاً')));
    }

    final service = FirestoreService();
    return Scaffold(
      appBar: AppBar(title: const Text('كورساتي'), centerTitle: true),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(tabs: [Tab(text: 'كورساتي'), Tab(text: 'المفضلة')]),
            Expanded(
              child: TabBarView(
                children: [
                  _PurchasedCourses(userId: user.uid, service: service),
                  _FavoriteCourses(userId: user.uid, service: service),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurchasedCourses extends StatelessWidget {
  final String userId;
  final FirestoreService service;
  const _PurchasedCourses({required this.userId, required this.service});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: service.watchMyCourseIds(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final ids = snapshot.data ?? <String>[];
        if (ids.isEmpty) return const _EmptyCourses();
        return FutureBuilder<List<Course>>(
          future: service.getCoursesByIds(ids),
          builder: (context, courseSnapshot) {
            if (courseSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final courses = courseSnapshot.data ?? <Course>[];
            if (courses.isEmpty) return const _EmptyCourses();
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: courses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final course = courses[index];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => context.push('/course/${course.id}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 180,
                          child: course.thumbnailUrl.isEmpty
                              ? Container(
                                  color: AppColors.emeraldLight,
                                  child: const Icon(Icons.menu_book, size: 60),
                                )
                              : Image.network(
                                  course.thumbnailUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: AppColors.emeraldLight,
                                    child: const Icon(Icons.menu_book, size: 60),
                                  ),
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      course.title,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      course.instructorName,
                                      style: const TextStyle(color: AppColors.muted),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${course.lessonsCount} درس',
                                      style: const TextStyle(color: AppColors.muted),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.play_circle_outline),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _FavoriteCourses extends StatelessWidget {
  final String userId;
  final FirestoreService service;
  const _FavoriteCourses({required this.userId, required this.service});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: service.watchFavoriteIds(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final ids = snapshot.data ?? <String>[];
        if (ids.isEmpty) return const Center(child: Text('لا توجد كورسات مفضلة بعد'));
        return FutureBuilder<List<Course>>(
          future: service.getCoursesByIds(ids),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final courses = snap.data ?? <Course>[];
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: courses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final course = courses[i];
                return ListTile(
                  tileColor: Colors.white,
                  leading: SizedBox(
                    width: 64,
                    height: 48,
                    child: Image.network(
                      course.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.menu_book),
                    ),
                  ),
                  title: Text(course.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(course.instructorName),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => context.push('/course/${course.id}'),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _EmptyCourses extends StatelessWidget {
  const _EmptyCourses();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 72, color: AppColors.muted),
            const SizedBox(height: 16),
            const Text(
              'لم تشترِ أي كورس بعد',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'الكورسات التي تشتريها ستظهر هنا',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
