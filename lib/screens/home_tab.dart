import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../models/user_profile.dart';
import '../models/course.dart';
import '../widgets/course_card.dart';
import '../theme/app_theme.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final firestore = FirestoreService();

    return SafeArea(
      child: StreamBuilder<UserProfile?>(
        stream: user == null ? const Stream.empty() : firestore.watchUserProfile(user.uid),
        builder: (context, profileSnap) {
          final profile = profileSnap.data;
          final name = profile?.name.isNotEmpty == true
              ? profile!.name
              : (user?.displayName?.isNotEmpty == true ? user!.displayName! : 'طالب');
          final photoUrl = profile?.photoUrl ?? '';
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('settings').doc('general').snapshots(),
            builder: (context, settingsSnap) {
              final settings = settingsSnap.data?.data() ?? const <String, dynamic>{};
              final platformName = (settings['siteTitle'] ?? settings['platformName'] ?? 'Fahimt').toString();
              final platformLogo = (settings['logoUrl'] ?? '').toString();
              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 23,
                            backgroundColor: AppColors.emerald,
                            backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                            child: photoUrl.isEmpty ? Text(name.isNotEmpty ? name[0] : 'ط', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)) : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  if (platformLogo.isNotEmpty)
                                    Padding(padding: const EdgeInsets.only(left: 6), child: Image.network(platformLogo, width: 22, height: 22, fit: BoxFit.contain)),
                                  Text(platformName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                                ]),
                                const SizedBox(height: 2),
                                Text('مرحبًا 👋 $name', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                              ],
                            ),
                          ),
                          IconButton(onPressed: () => context.push('/notifications'), icon: const Icon(Icons.notifications_none)),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
                      child: Text('كورساتي', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 16.5)),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: StreamBuilder<List<String>>(
                      stream: user == null ? const Stream.empty() : firestore.watchMyCourseIds(user.uid),
                      builder: (context, snap) {
                        final ids = snap.data ?? [];
                        if (ids.isEmpty) return const Padding(padding: EdgeInsets.symmetric(horizontal: 18), child: Text('لسه مشتريتش أي كورس', style: TextStyle(color: AppColors.muted, fontSize: 13)));
                        return SizedBox(
                          height: 190,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            itemCount: ids.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 12),
                            itemBuilder: (context, i) => FutureBuilder<Course?>(
                              future: firestore.getCourse(ids[i]),
                              builder: (context, courseSnap) {
                                final c = courseSnap.data;
                                if (c == null) return const SizedBox(width: 210);
                                return SizedBox(width: 210, child: CourseCard(course: c, onTap: () => context.push('/course/${c.id}')));
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 26, 18, 14),
                      child: Text('جديدنا', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 16.5)),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    sliver: StreamBuilder<List<Course>>(
                      stream: firestore.watchCourses(),
                      builder: (context, snap) {
                        final courses = snap.data ?? [];
                        return SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: .72),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => CourseCard(course: courses[i], onTap: () => context.push('/course/${courses[i].id}')),
                            childCount: courses.length,
                          ),
                        );
                      },
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 30)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
