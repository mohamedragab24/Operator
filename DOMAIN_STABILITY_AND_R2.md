# ثبات روابط الكورسات وR2

- التطبيق لا يعتمد على دومين Vercel لفتح الكورس داخل التطبيق.
- الرابط الثابت من المنصة إلى التطبيق هو: `fahmny://course/COURSE_ID`.
- بيانات الكورس والمحاضرات لها نسخة احتياطية في R2 على `courses/{courseId}/manifest.json`.
- حالة الشراء يتم التحقق منها في Firebase أولًا. عند تعذر قراءة Firestore، Cloud Function تستخدم entitlement recovery في R2.
- لا يتم وضع R2 credentials داخل التطبيق.
