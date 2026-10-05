# مسار — Flutter App

مشروع Flutter حقيقي، مربوط بمشروع Firebase بتاعك (`studio-7708799057-99672`)، مطابق للتصميم اللي شوفته في النموذج التفاعلي (HTML) قبل كده.

## اللي أنا عملته
- ملفات `google-services.json` و `GoogleService-Info.plist` اللي بعتهملي، حطيتهم في المكان الصح جوه المشروع.
- كل الشاشات (تسجيل دخول/حساب/رئيسية/كورسات/تفاصيل كورس/مشغل فيديو) مكتوبة ومربوطة فعليًا بـ Firebase Auth و Firestore.
- مشغل الفيديو (`lib/screens/lesson_player_screen.dart`) بيطلب رابط فيديو مؤقت من Cloud Function حقيقية (`functions/index.js`) بدل ما يكون فيه رابط ثابت — وده هو نظام الحماية اللي طلبته في الـ spec الأول.
- Firestore Security Rules و Storage Rules (`firestore.rules`, `storage.rules`) بتمنع أي حد يوصل لملف الفيديو مباشرة حتى لو كان مسجل دخول — الرابط الوحيد بيطلع من الـ Cloud Function.
- حماية الشاشة على أندرويد (`FLAG_SECURE`) شغالة أثناء تشغيل الفيديو (بتمنع لقطة شاشة أو تسجيل الشاشة).

## اللي أنت محتاج تعمله (بالترتيب)

### 1. جهّز جهازك
```bash
# ثبّت Flutter SDK لو مش مثبت: https://docs.flutter.dev/get-started/install
flutter doctor
```
لبناء نسخة الأيفون تحديدًا: لازم يكون عندك **Mac** فيه **Xcode** وحساب **Apple Developer**. أندرويد ممكن تبنيه من ويندوز أو ماك أو لينكس عادي.

### 2. ثبّت المكتبات
```bash
cd masar_app
flutter pub get
```

### 3. فعّل خدمات Firebase (من console.firebase.google.com، مشروع studio-7708799057-99672)
- **Authentication** → فعّل طريقة "البريد الإلكتروني/كلمة المرور".
- **Firestore Database** → أنشئه في وضع Production.
- **Storage** → أنشئ الـ bucket (لو لسه مش منشأ).
- **الخطة** → لازم تكون على خطة **Blaze** (Pay-as-you-go) عشان Cloud Functions تشتغل. الاستخدام البسيط بيفضل غالبًا في الحد المجاني، بس الخطة نفسها لازم تتفعّل.

### 4. جهّز بيانات تجريبية في Firestore
حط داتا زي الشكل ده (يدويًا من الـ Console، أو Script بسيط):
```
courses/{courseId}
  title, description, instructorName, category, thumbnailUrl,
  price, rating, studentsCount, lessonsCount, durationLabel,
  features: [string], isPublished: true

courses/{courseId}/lessons/{lessonId}
  title, order, durationSeconds, isPreview, storagePath
  (storagePath = المسار داخل Storage، مثال: "courses/c1/lessons/l3.mp4")

purchases/{uid}_{courseId}
  uid, courseId, status: "completed"
  (ده بيتكتب تلقائيًا من الـ Cloud Function onPaymentCompleted —
   منقترحش تكتبه يدوي غير للتجربة بس)
```

### 5. ارفع فيديوهات الدروس على Storage
ارفعها تحت مسار زي `courses/c1/lessons/l3.mp4` — **مش عام (public)**، لأن `storage.rules` بيمنع القراءة المباشرة أصلًا؛ الوصول بيتم بس عن طريق الـ Cloud Function.

### 6. Deploy الـ Cloud Function والقواعد
```bash
npm install -g firebase-tools
firebase login
cd masar_app
firebase init   # اختار Functions + Firestore + Storage، اربطهم بمشروع studio-7708799057-99672
firebase deploy --only functions,firestore:rules,storage:rules
```

### 7. الروابط العميقة (Deep Links)
- **أندرويد**: زوّد الـ intent-filter من `android/app_manifest_snippet.xml` جوه `AndroidManifest.xml`، وحط ملف `assetlinks.json` على دومين الموقع بتاعك (التفاصيل في نفس الملف).
- **iOS**: فعّل خاصية **Associated Domains** في Xcode (`applinks:YOURDOMAIN.com`)، وحط ملف `apple-app-site-association` على نفس الدومين.

هنا لازم يبقى عندك **دومين حقيقي** للموقع (مش رابط Vercel المحمي اللي بعته)، لأن الروابط العميقة محتاجة دومين تقدر تتحكم فيه وتحط عليه الملفين دول.

### 8. شغّل المشروع
```bash
flutter run
```

## ملاحظة عن الحماية على iOS
على أندرويد، `FLAG_SECURE` بيمنع لقطة الشاشة وتسجيلها فعليًا. على iOS، مفيش API من أبل تمنع تسجيل الشاشة بشكل كامل — أقصى حاجة ممكنة هي إنك تكتشف إن المستخدم بدأ يسجل الشاشة (`UIScreen.capturedDidChangeNotification`) وتوقف الفيديو وقتها. ده محتاج شوية كود Swift بسيط مش موجود في المكتبات الجاهزة — لو عايز، أقدر أكتبهولك في خطوة منفصلة.

## رفع المشروع على GitHub
```bash
cd masar_app
git init
git add .
git commit -m "أول نسخة من تطبيق مسار"
git branch -M main
git remote add origin <رابط الريبو بتاعك على GitHub>
git push -u origin main
```
ملف `.gitignore` مظبوط بالفعل عشان ميرفعش ملفات البناء المؤقتة.

**ملاحظة أمان بسيطة:** ملفات `google-services.json` و `GoogleService-Info.plist` مرفوعة جوه المشروع (مطلوبة عشان يشتغل). القيم اللي فيها مش أسرار بالمعنى الحرفي (جوجل بتقول رسميًا إنها آمنة تتحط في ريبو)، لكن الأفضل إنك تخلي الريبو **Private** لحد ما التطبيق يخرج للجمهور، بدل ما يبقى عام من الأول.

## الحالة الحالية (إيه اللي جاهز وإيه الباقي)

**جاهز وشغال فعليًا:**
- تسجيل دخول/حساب بـ Firebase Auth الحقيقي (نفس حسابات عملاء الموقع بالظبط)
- سحب بيانات العميل (الاسم، البريد، الهاتف) من `users/{uid}` في Firestore، وتحديثها أول ما يسجل دخول من التطبيق
- عرض الكورسات المشترك فيها + نسبة التقدم، مسحوبة Live من Firestore
- مشغل فيديو بيطلب رابط مؤقت من Cloud Function بعد التأكد من الشراء (مفيش رابط ثابت في التطبيق خالص)
- حماية الشاشة على **كل الصفحات**: أندرويد `FLAG_SECURE` (منع كامل للقطة الشاشة والتسجيل)، آيفون كشف فعلي لبدء التسجيل ولقطة الشاشة مع تغطية المحتوى فورًا (آبل مش بتسمح بمنعها 100%، بس ده أقصى حماية ممكنة تقنيًا)

**لسه ناقص (يستاهل تركيز الخطوة الجاية):**
1. **هجرة العملاء القدامى** (لو فيه عملاء مسجلين على الموقع بطريقة تانية غير Firebase Auth مباشر) — قولتلي إنهم الاتنين، يبقى الأغلب هيشتغلوا عادي، بس لسه محتاجين نتأكد بتجربة حساب حقيقي واحد على الأقل.
2. **رفع فيديوهات الدروس الفعلية** على Storage وربط `storagePath` بكل درس في Firestore.
3. **لوحة الإدارة** لسه ماتعملتش (لإدارة المستخدمين/الكورسات/المبيعات).
4. **الدومين الحقيقي للروابط العميقة** — الروابط العميقة (فتح رابط كورس من الموقع فيفتح التطبيق) محتاجة دومين تقدر تتحكم فيه (مش رابط Vercel Preview المحمي) عشان تحط عليه ملفات التحقق.
5. **الـ Build الفعلي**: لسه محدش عمل `flutter build` أو جربه على جهاز حقيقي — أول تجربة فعلية هتكشف أي أخطاء صغيرة محتاجة تصليح.

```
lib/
  main.dart                 نقطة الدخول + تهيئة Firebase
  app_router.dart           كل المسارات (go_router)
  theme/app_theme.dart      ألوان وخطوط البراند
  models/                   Course, Lesson
  services/
    auth_service.dart       تسجيل دخول/حساب/خروج
    firestore_service.dart  قراءة الكورسات/الدروس/المشتريات/التقدم
    video_service.dart      طلب رابط الفيديو المؤقت من Cloud Function
    deep_link_service.dart  فتح رابط كورس من الموقع
  screens/                  كل الشاشات
functions/index.js          Cloud Function الحماية الفعلية
firestore.rules             قواعد أمان Firestore
storage.rules                قواعد أمان Storage
```

## نظام تحديث التطبيق

تم توحيد GitHub Actions في Workflow واحد فقط: `.github/workflows/build-apk.yml`.
كل Build على `main` ينشئ APK برقم `versionCode` مساوي لرقم تشغيل GitHub Actions، ثم ينشئ GitHub Release ويرفع `app-release.apk`.

التطبيق يفحص أحدث Release عند التشغيل على Android، وإذا وجد نسخة أحدث يظهر زر **تحديث الآن** لتحميل الـAPK.

> قبل النشر العام، استخدم keystore إنتاجي ثابت في GitHub Secrets ووقّع كل الإصدارات بنفس المفتاح، وإلا قد لا يسمح Android بتثبيت التحديث فوق النسخة القديمة.
