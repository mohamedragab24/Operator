# تحديث تطبيق Flutter من GitHub Actions

## كيف يعمل

- كل `push` على `main` يشغل Workflow واحد فقط: `Build and Release Fahmani APK`.
- كل تشغيل ناجح يحصل على `versionCode` يساوي رقم تشغيل GitHub Actions.
- يتم إنشاء GitHub Release بالصيغة `build-<run_number>`.
- يتم رفع `app-release.apk` داخل الـRelease.
- التطبيق يفحص آخر Release عند التشغيل على Android.
- إذا كان `versionCode` الموجود على الهاتف أقل من آخر Release، تظهر رسالة **تحديث جديد متاح**.
- زر **تحديث الآن** يفتح رابط APK في تطبيق خارجي/المتصفح لتحميل النسخة الجديدة وتثبيتها.

## مهم جدًا: توقيع Android

الـWorkflow الحالي يبني باستخدام توقيع Flutter debug الافتراضي إذا لم تتم إضافة keystore للإصدار. هذا مناسب للاختبار، لكنه **ليس مناسبًا للتحديثات بين نسخ إنتاجية** لأن كل بيئة GitHub جديدة قد تستخدم مفتاح debug مختلف.

قبل نشر التطبيق للمستخدمين، يجب إضافة keystore إنتاجي ثابت إلى GitHub Secrets ثم تعديل خطوة Gradle لاستخدامه. يجب أن تكون كل نسخ التطبيق المستقبلية موقعة بنفس المفتاح حتى يستطيع Android تحديث النسخة الموجودة بدل اعتبارها تطبيقًا مختلفًا.

## لو كان Repository خاصًا

فحص GitHub Releases من داخل التطبيق يحتاج API authentication أو نقل ملف الإصدار إلى Firebase Storage/Hosting. الكود الحالي يفترض أن مستودع GitHub يمكن الوصول إلى Releases الخاصة به بدون تسجيل دخول من التطبيق.
