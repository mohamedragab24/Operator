import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/firestore_service.dart';
import '../models/course.dart';
import '../widgets/course_card.dart';
import '../theme/app_theme.dart';

class CoursesTab extends StatefulWidget {
  const CoursesTab({super.key});

  @override
  State<CoursesTab> createState() => _CoursesTabState();
}

class _CoursesTabState extends State<CoursesTab> {
  String _category = 'الكل';
  final _categories = const ['الكل', 'البرمجة والتقنية', 'الرياضيات والعلوم', 'الذكاء الاصطناعي', 'اللغات والآداب', 'التصميم والمونتاج', 'إدارة الأعمال والتسويق'];
  final _firestore = FirestoreService();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
            child: Row(children: [
              Text('الكورسات', style: Theme.of(context).textTheme.headlineSmall),
            ]),
          ),
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final cat = _categories[i];
                final selected = cat == _category;
                return ChoiceChip(
                  label: Text(cat),
                  selected: selected,
                  onSelected: (_) => setState(() => _category = cat),
                  selectedColor: AppColors.ink,
                  labelStyle: TextStyle(color: selected ? AppColors.paper : AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12.5),
                  backgroundColor: AppColors.white,
                  side: const BorderSide(color: AppColors.line),
                );
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Course>>(
              stream: _firestore.watchCourses(category: _category),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'جاري إعادة الاتصال وتحميل الكورسات من منصة فهمت...\nسيتم تحديث القائمة تلقائيًا عند عودة الاتصال.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final courses = snap.data!;
                if (courses.isEmpty) {
                  return const Center(
                    child: Text(
                      'لا يوجد كورسات في هذا التصنيف',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(18),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: .72,
                  ),
                  itemCount: courses.length,
                  itemBuilder: (context, i) => CourseCard(course: courses[i], onTap: () => context.push('/course/${courses[i].id}')),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
