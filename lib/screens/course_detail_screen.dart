import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/firestore_service.dart';
import '../models/course.dart';
import '../models/lesson.dart';
import '../models/user_profile.dart';
import '../theme/app_theme.dart';

class CourseDetailScreen extends StatefulWidget {
  final String courseId;
  final int initialLessonNumber;
  const CourseDetailScreen({super.key, required this.courseId, this.initialLessonNumber = 1});

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  bool _openedInitialLesson = false;
  bool _openedPurchasedLesson = false;
  bool _following = false;
  final FirestoreService _fs = FirestoreService();
  late Future<Course?> _courseFuture;
  Future<bool>? _purchasedFuture;

  @override
  void initState() {
    super.initState();
    _courseFuture = _fs.getCourse(widget.courseId);
  }

  @override
  Widget build(BuildContext context) {
    final firestore = _fs;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      body: FutureBuilder<Course?>(
        future: _courseFuture,
        builder: (context, courseSnap) {
          if (courseSnap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final course = courseSnap.data;
          if (course == null) {
            return SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.cloud_off_outlined, size: 44, color: AppColors.muted),
                    const SizedBox(height: 12),
                    const Text('تعذر تحميل بيانات الكورس الآن', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    const Text('تحقق من الاتصال ثم أعد المحاولة. بياناتك ومشترياتك محفوظة.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    const SizedBox(height: 14),
                    FilledButton(onPressed: () => setState(() { _courseFuture = firestore.getCourse(widget.courseId); _purchasedFuture = null; }), child: const Text('إعادة المحاولة')),
                    TextButton(onPressed: () => context.go('/'), child: const Text('الرئيسية')),
                  ]),
                ),
              ),
            );
          }

          return FutureBuilder<bool>(
            future: _purchasedFuture ??= (uid == null ? Future.value(false) : firestore.hasPurchased(uid, widget.courseId)),
            builder: (context, purchasedSnap) {
              final purchased = purchasedSnap.data ?? false;
              if (purchased && !_openedPurchasedLesson && widget.initialLessonNumber <= 1) {
                _openedPurchasedLesson = true;
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  if (!mounted) return;
                  final lessons = await firestore.getLessons(widget.courseId);
                  if (!mounted || lessons.isEmpty) return;
                  context.push('/course/${widget.courseId}/lesson/${lessons.first.id}');
                });
              }
              return CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 210,
                    pinned: true,
                    backgroundColor: AppColors.ink,
                    leading: IconButton(icon: const Icon(Icons.arrow_forward, color: Colors.white), onPressed: () => context.pop()),
                    flexibleSpace: FlexibleSpaceBar(
                      background: CachedNetworkImage(imageUrl: course.thumbnailUrl, fit: BoxFit.cover),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(course.title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 21)),
                          const SizedBox(height: 8),
                          Text('المفهّم: ${course.instructorName.isEmpty ? 'مفهّم' : course.instructorName}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                          const SizedBox(height: 14),
                          Row(children: [
                            const Icon(Icons.star, color: AppColors.gold, size: 15),
                            Text(' ${course.rating}   ', style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text('${course.studentsCount} طالب   ', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                            Text(course.durationLabel, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                          ]),
                          const SizedBox(height: 16),
                          Text(course.description, style: const TextStyle(height: 1.8, fontSize: 13.5, color: Color(0xFF3C4650))),
                          const SizedBox(height: 20),
                          ...course.features.map((f) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(children: [
                                  const Icon(Icons.check_circle, color: AppColors.emerald, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(f, style: const TextStyle(fontSize: 13))),
                                ]),
                              )),
                          const SizedBox(height: 20),
                          if (course.instructorId.isNotEmpty)
                            StreamBuilder<UserProfile?>(
                              stream: firestore.watchUserProfile(course.instructorId),
                              builder: (context, ps) {
                                final teacher = ps.data;
                                if (teacher == null) return const SizedBox.shrink();
                                return Card(
                                  margin: EdgeInsets.zero,
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Row(children: [
                                      CircleAvatar(radius: 28, backgroundImage: teacher.photoUrl.isNotEmpty ? NetworkImage(teacher.photoUrl) : null, child: teacher.photoUrl.isEmpty ? Text(teacher.name.isNotEmpty ? teacher.name[0] : 'م') : null),
                                      const SizedBox(width: 12),
                                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(teacher.name.isEmpty ? course.instructorName : teacher.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 3),
                                        Text(teacher.bio.isEmpty ? 'مُفهّم ناشر الكورس' : teacher.bio, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                                        const SizedBox(height: 5),
                                        StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
                                          stream: FirebaseFirestore.instance.collection('users').doc(course.instructorId).collection('followers').snapshots(),
                                          builder: (_, fs) => Text('${fs.data?.docs.length ?? 0} متابع  •  تقييم ${teacher.rating.toStringAsFixed(1)}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                                        ),
                                      ])),
                                      FilledButton.tonal(onPressed: () async {
                                        final me = FirebaseAuth.instance.currentUser;
                                        if (me == null || me.uid == course.instructorId) return;
                                        final ref = FirebaseFirestore.instance.collection('users').doc(course.instructorId).collection('followers').doc(me.uid);
                                        if (_following) { await ref.delete(); } else { await ref.set({'uid': me.uid, 'createdAt': FieldValue.serverTimestamp()}); }
                                        if (mounted) setState(() => _following = !_following);
                                      }, child: Text(_following ? 'متابَع' : 'متابعة')),
                                    ]),
                                  ),
                                );
                              },
                            ),
                          const SizedBox(height: 20),
                          Text('محتوى الكورس', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 16.5)),
                          StreamBuilder<List<Lesson>>(
                            stream: firestore.watchLessons(widget.courseId),
                            builder: (context, lessonSnap) {
                              final lessons = lessonSnap.data ?? [];
                              if (!_openedInitialLesson && widget.initialLessonNumber >= 2 && lessons.isNotEmpty) {
                                final matches = lessons.where((l) => l.order == widget.initialLessonNumber).toList();
                                final target = matches.isEmpty ? null : matches.first;
                                if (target != null) {
                                  _openedInitialLesson = true;
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (mounted) context.push('/course/${widget.courseId}/lesson/${target.id}');
                                  });
                                }
                              }
                              return Column(
                                children: lessons.map((l) {
                                  final locked = !purchased && !l.isPreview;
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      radius: 15,
                                      backgroundColor: AppColors.paperDim,
                                      child: Text('${l.order}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                                    ),
                                    title: Text(l.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                                    subtitle: Text(l.durationLabel, style: const TextStyle(fontSize: 11.5)),
                                    trailing: Icon(locked ? Icons.lock_outline : Icons.play_circle_outline, size: 18, color: AppColors.muted),
                                    onTap: locked ? null : () => context.push('/course/${widget.courseId}/lesson/${l.id}'),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                          const SizedBox(height: 90),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
