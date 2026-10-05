import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/course.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class FavoritesTab extends StatelessWidget {
  const FavoritesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text('يجب تسجيل الدخول أولاً'),
        ),
      );
    }

    final service = FirestoreService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('المفضلة'),
        centerTitle: true,
      ),
      body: StreamBuilder<List<String>>(
        stream: service.watchFavoriteIds(user.uid),
        builder: (context, favoriteSnapshot) {
          if (favoriteSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final ids = favoriteSnapshot.data ?? [];

          if (ids.isEmpty) {
            return _EmptyFavorites();
          }

          return FutureBuilder<List<Course>>(
            future: service.getCoursesByIds(ids),
            builder: (context, courseSnapshot) {
              if (courseSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              final courses = courseSnapshot.data ?? [];

              if (courses.isEmpty) {
                return _EmptyFavorites();
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: courses.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  return _FavoriteCourseCard(
                    course: courses[index],
                    service: service,
                    uid: user.uid,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _FavoriteCourseCard extends StatelessWidget {
  final Course course;
  final FirestoreService service;
  final String uid;

  const _FavoriteCourseCard({
    required this.course,
    required this.service,
    required this.uid,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          context.push('/course/${course.id}');
        },
        child: Row(
          children: [
            SizedBox(
              width: 120,
              height: 100,
              child: course.thumbnailUrl.isEmpty
                  ? Container(
                      color: AppColors.emeraldLight,
                      child: const Icon(
                        Icons.menu_book,
                        size: 40,
                      ),
                    )
                  : Image.network(
                      course.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return Container(
                          color: AppColors.emeraldLight,
                          child: const Icon(
                            Icons.menu_book,
                            size: 40,
                          ),
                        );
                      },
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      course.instructorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.star,
                          size: 16,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          course.rating.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 12),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'إزالة من المفضلة',
                          onPressed: () async {
                            await service.setFavorite(
                              uid,
                              course.id,
                              false,
                            );
                          },
                          icon: const Icon(
                            Icons.favorite,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFavorites extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.favorite_border,
              size: 72,
              color: AppColors.muted,
            ),
            const SizedBox(height: 16),
            const Text(
              'لا توجد كورسات في المفضلة',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'أضف الكورسات التي تريد الرجوع إليها لاحقًا',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
