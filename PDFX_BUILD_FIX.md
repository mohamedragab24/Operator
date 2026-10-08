# إصلاح فشل البناء: pdfx:compileReleaseKotlin

السبب: pdfx 2.9.2 مكتوب لـ Flutter 3.27+ (يستخدم onSurfaceAvailable/onSurfaceCleanup)، والمشروع مثبّت على Flutter 3.24.5 (الأسماء فيه onSurfaceCreated/onSurfaceDestroyed).
الحل: خطوة في workflow (`Patch pdfx for this Flutter version`) تعدّل أسماء الدالتين في ملف pdfx داخل pub-cache قبل البناء، وتتخطى نفسها تلقائيًا لو رفعت Flutter إلى 3.27 أو أحدث.
