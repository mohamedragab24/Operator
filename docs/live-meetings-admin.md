# المحاضرات المباشرة + لوحة الأدمن

تمت إضافة بنية المحاضرات المباشرة للتطبيق مع:
- قائمة محاضرات مرتبطة بـ `istifhams.meetingTime`.
- دخول قبل الموعد بـ5 دقائق وحتى 6 ساعات بعده.
- رابط deep-link بصيغة `fahmny://meeting/<requestId>`.
- Jitsi Meet Flutter SDK للانضمام من التطبيق.
- حماية Android عبر `FLAG_SECURE` لكل Activity بما فيها Activities التي يفتحها SDK قدر الإمكان.
- Firebase Cloud Messaging لتسجيل أجهزة المستخدمين.
- إشعارات مجدولة للمحاضرات وللحملات.
- حظر المستخدم مع السبب والمدة وتعطيل حساب Firebase Authentication.
- إنشاء حساب أدمن من داخل لوحة الأدمن عبر Cloud Function.
- مراجعة الكورسات الحالية من لوحة الأدمن.
- Webhook لتخزين تسجيلات JaaS في Firebase Storage وبياناتها في Firestore.

## متطلبات JaaS

ضع المتغيرات السرية في بيئة Cloud Functions:
- `JAAS_APP_ID`
- `JAAS_KEY_ID`
- `JAAS_PRIVATE_KEY`

ويجب تسجيل webhook:
`https://<region>-<project>.cloudfunctions.net/jaasRecordingWebhook`

تسجيل اجتماعات JaaS خدمة مدفوعة؛ التسجيل يحتفظ به JaaS مؤقتًا، لذلك الـ webhook يحفظ نسخة MP4 في Firebase Storage.
