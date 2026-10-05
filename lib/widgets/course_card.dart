import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/course.dart';
import '../theme/app_theme.dart';

class CourseCard extends StatelessWidget {
  final Course course;
  final VoidCallback onTap;
  const CourseCard({super.key, required this.course, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: CachedNetworkImage(
                imageUrl: course.thumbnailUrl,
                fit: BoxFit.cover,
                placeholder: (c, _) => Container(color: AppColors.paperDim),
                errorWidget: (c, _, __) => Container(color: AppColors.paperDim),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.star, color: AppColors.gold, size: 13),
                      const SizedBox(width: 3),
                      Text('${course.rating}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                      const SizedBox(width: 6),
                      Text('· ${course.studentsCount} طالب', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('${course.price.toStringAsFixed(0)} ج.م',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.emeraldDark, fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
