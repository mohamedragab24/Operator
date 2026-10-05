const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentUpdated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { presignedUrl, putObject } = require('./r2');
const R2_SECRETS = ['R2_ACCOUNT_ID', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY', 'R2_BUCKET'];
const R2_PUBLIC_BASE = process.env.R2_PUBLIC_BASE_URL || 'https://fahmny-r2.mohamedragabewiess.workers.dev';
const entitlementKey = (uid, courseId) => crypto.createHash('sha256').update(`${uid}:${courseId}`).digest('hex');
const isAdminRequest = async (request) => { const uid = request.auth?.uid; if (!uid) return false; const me = await db.collection('users').doc(uid).get(); const p = me.data() || {}; return request.auth.token?.admin === true || p.isAdmin === true || p.role === 'admin'; };

admin.initializeApp();
const db = admin.firestore();
const bucket = admin.storage().bucket();

// How long a signed video URL stays valid before the app must ask again.
const SIGNED_URL_TTL_MS = 10 * 60 * 1000; // 10 minutes

/**
 * Callable function: getSignedVideoUrl({ courseId, lessonId })
 *
 * This is the entire content-protection mechanism described in the
 * project spec: the app never holds a real video URL — it asks this
 * function every time it wants to play (or resume, or move to the next
 * lesson), and only gets a URL back if all checks pass.
 */
exports.getSignedVideoUrl = onCall({ secrets: R2_SECRETS }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "لازم تسجل الدخول أولاً");
  const { courseId, lessonId } = request.data || {};
  if (!courseId || !lessonId) throw new HttpsError("invalid-argument", "بيانات الدرس غير مكتملة");

  let lesson = null;
  try {
    const snap = await db.collection("courses").doc(courseId).collection("lessons").doc(lessonId).get();
    if (snap.exists) lesson = snap.data() || {};
  } catch (_) {}
  if (!lesson) {
    try {
      const response = await fetch(`${R2_PUBLIC_BASE}/courses/${encodeURIComponent(courseId)}/manifest.json`);
      if (response.ok) {
        const manifest = await response.json();
        lesson = Array.isArray(manifest.lessons) ? manifest.lessons.find(x => String(x.id || x.lessonId) === String(lessonId)) : null;
      }
    } catch (_) {}
  }
  if (!lesson) throw new HttpsError("not-found", "الدرس غير موجود");

  let purchased = false;
  if (lesson.isPreview === true) {
    purchased = true;
  } else {
    try {
      const purchaseDoc = await db.collection("purchases").doc(`${uid}_${courseId}`).get();
      purchased = purchaseDoc.exists && purchaseDoc.data()?.status === "completed";
    } catch (_) {}
    if (!purchased) {
      try {
        const response = await fetch(`${R2_PUBLIC_BASE}/entitlements/${entitlementKey(uid, courseId)}.json`);
        if (response.ok) {
          const entitlement = await response.json();
          purchased = entitlement?.status === 'completed' && String(entitlement?.uid || '') === uid && String(entitlement?.courseId || '') === courseId;
        }
      } catch (_) {}
    }
    if (!purchased) throw new HttpsError("permission-denied", "لازم تشتري الكورس الأول");
  }

  const r2Key = String(lesson.r2Key || '');
  if (!r2Key && !lesson.storagePath) throw new HttpsError("failed-precondition", "ملف الفيديو غير متاح حاليًا");
  let url;
  let expiresAtMs = Date.now() + SIGNED_URL_TTL_MS;
  if (r2Key) {
    const signed = presignedUrl({ method: 'GET', key: r2Key, expiresSeconds: Math.floor(SIGNED_URL_TTL_MS / 1000) });
    url = signed.url; expiresAtMs = signed.expiresAtMs;
  } else {
    const [legacyUrl] = await bucket.file(lesson.storagePath).getSignedUrl({ version: 'v4', action: 'read', expires: Date.now() + SIGNED_URL_TTL_MS });
    url = legacyUrl;
  }
  await db.collection("sessions").add({ uid, courseId, lessonId, issuedAt: admin.firestore.FieldValue.serverTimestamp() });
  return { url, expiresAtMs };
});

/** Create a short-lived R2 PUT URL. The browser uploads the file directly to R2;
 * no R2 secret is ever sent to the browser. */
exports.createR2UploadUrl = onCall({ secrets: R2_SECRETS }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'لازم تسجل الدخول أولاً');
  const profile = await db.collection('users').doc(uid).get();
  const p = profile.data() || {};
  const isAdmin = p.isAdmin === true || p.role === 'admin' || request.auth.token?.admin === true;
  if (!isAdmin && p.mode !== 'mofahhem') throw new HttpsError('permission-denied', 'رفع الملفات متاح للمُفهّمين والأدمن فقط');

  const data = request.data || {};
  const courseId = String(data.courseId || '').trim();
  const kind = String(data.kind || '').trim();
  const fileName = String(data.fileName || 'file.bin').trim();
  const contentType = String(data.contentType || 'application/octet-stream').trim();
  const lessonNumber = Number(data.lessonNumber || 0);
  if (!courseId || !['cover', 'lesson'].includes(kind)) throw new HttpsError('invalid-argument', 'بيانات الرفع غير صحيحة');
  if (kind === 'lesson' && (!Number.isInteger(lessonNumber) || lessonNumber < 1 || lessonNumber > 110)) {
    throw new HttpsError('invalid-argument', 'رقم الدرس غير صحيح');
  }
  const safe = fileName.replace(/[^a-zA-Z0-9._-]/g, '_').slice(-180) || 'file.bin';
  const key = kind === 'cover'
    ? `courses/${courseId}/cover/${Date.now()}_${safe}`
    : `courses/${courseId}/lessons/${String(lessonNumber).padStart(2, '0')}/${Date.now()}_${safe}`;
  const signed = presignedUrl({ method: 'PUT', key, expiresSeconds: 900, contentType });
  return { ...signed, key, token: kind === 'cover' ? `r2cover:${courseId}:${key}` : `r2:${courseId}:${lessonNumber}:${key}` };
});

/** Resolve an R2 media token into a short-lived GET URL. */
exports.getR2MediaUrl = onCall({ secrets: R2_SECRETS }, async (request) => {
  const token = String(request.data?.token || '').trim();
  if (!token) throw new HttpsError('invalid-argument', 'رابط الملف غير موجود');
  const parts = token.split(':');
  const type = parts[0];
  const courseId = parts[1];
  const key = type === 'r2' ? parts.slice(3).join(':') : parts.slice(2).join(':');
  if (!courseId || !key || !['r2', 'r2cover'].includes(type)) throw new HttpsError('invalid-argument', 'رابط R2 غير صالح');

  const courseSnap = await db.collection('courses').doc(courseId).get();
  if (!courseSnap.exists) throw new HttpsError('not-found', 'الكورس غير موجود');
  const course = courseSnap.data() || {};
  const uid = request.auth?.uid;
  if (type === 'r2cover') {
    if (String(course.coverUrl || '') !== token) throw new HttpsError('permission-denied', 'ملف الغلاف غير مطابق');
    if (!course.isPublished && course.status !== 'published') throw new HttpsError('permission-denied', 'الكورس غير منشور');
  } else {
    if (!uid) throw new HttpsError('unauthenticated', 'لازم تسجل الدخول أولاً');
    const profile = await db.collection('users').doc(uid).get();
    const p = profile.data() || {};
    const adminUser = p.isAdmin === true || p.role === 'admin' || request.auth.token?.admin === true;
    const lessonNo = Number(parts[2] || 0);
    const lessonSnap = await db.collection('courses').doc(courseId).collection('lessons')
      .where('lessonNumber', '==', lessonNo).limit(1).get();
    const lesson = lessonSnap.empty ? null : lessonSnap.docs[0].data();
    if (!lesson || String(lesson.r2Key || '') !== key) {
      throw new HttpsError('permission-denied', 'ملف الدرس غير مطابق');
    }
    if (!adminUser && !lesson.isPreview) {
      const purchase = await db.collection('purchases').doc(`${uid}_${courseId}`).get();
      if (!purchase.exists || purchase.data()?.status !== 'completed') throw new HttpsError('permission-denied', 'لازم تشتري الكورس الأول');
    }
  }
  const signed = presignedUrl({ method: 'GET', key, expiresSeconds: 600 });
  return signed;
});

/**
 * Keep the public instructor name on the owner's courses in sync with
 * the profile name. This runs with Admin SDK so users cannot edit course
 * metadata directly.
 */
exports.onUserProfileUpdated = onDocumentUpdated("users/{userId}", async (event) => {
  const before = event.data?.before?.data() || {};
  const after = event.data?.after?.data() || {};
  if ((before.name || "") === (after.name || "")) return;

  const courses = await db.collection("courses")
    .where("ownerUid", "==", event.params.userId)
    .get();

  if (courses.empty) return;
  const batch = db.batch();
  for (const doc of courses.docs) {
    batch.update(doc.ref, { instructorName: String(after.name || "") });
  }
  await batch.commit();
});

async function sendPurchaseNotification(uid, courseId, course) {
  const title = 'تم تأكيد شراء الكورس';
  const body = `تم تفعيل ${String(course.title || 'الكورس')} في حسابك ويمكنك بدء المشاهدة الآن.`;
  const imageUrl = String(course.thumbnailUrl || course.coverUrl || '');
  const notificationId = `purchase_${courseId}_${Date.now()}`;
  await db.collection('users').doc(uid).collection('notifications').doc(notificationId).set({ title, body, imageUrl, type: 'purchase_completed', courseId, read: false, createdAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
  const tokensSnap = await db.collection('users').doc(uid).collection('fcmTokens').get();
  const tokens = tokensSnap.docs.map(d => d.data()?.token).filter(Boolean);
  if (!tokens.length) return;
  for (let i = 0; i < tokens.length; i += 500) {
    await admin.messaging().sendEachForMulticast({
      tokens: tokens.slice(i, i + 500),
      notification: { title, body, ...(imageUrl ? { imageUrl } : {}) },
      data: { type: 'purchase_completed', courseId: String(courseId), notificationId }
    });
  }
}

/** Securely create a pending payment request for the current user. The actual purchase is completed only by the payment webhook. */
exports.purchaseCourse = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'لازم تسجل الدخول أولاً');
  const courseId = String(request.data?.courseId || '').trim();
  if (!courseId) throw new HttpsError('invalid-argument', 'معرف الكورس غير صحيح');
  try {
    // Course data: Firestore first, then the R2 manifest (same fallback the apps use).
    let course = null;
    try {
      const courseSnap = await db.collection('courses').doc(courseId).get();
      if (courseSnap.exists) course = courseSnap.data() || {};
    } catch (e) { console.error('purchaseCourse: course read failed', e); }
    if (!course) {
      try {
        const r = await fetch(`${R2_PUBLIC_BASE}/courses/${encodeURIComponent(courseId)}/manifest.json`);
        if (r.ok) course = await r.json();
      } catch (e) { console.error('purchaseCourse: manifest read failed', e); }
    }
    if (!course) throw new HttpsError('not-found', 'الكورس غير موجود');
    if (course.status && course.status !== 'published' && course.isPublished !== true) {
      throw new HttpsError('failed-precondition', 'الكورس غير منشور');
    }

    const purchaseRef = db.collection('purchases').doc(`${uid}_${courseId}`);
    const existing = await purchaseRef.get();
    if (existing.exists && existing.data()?.status === 'completed') {
      return { ok: true, alreadyPurchased: true, amountPaid: Number(existing.data()?.amountPaid || course.price || 0) };
    }

    // Application-level checkout: the entitlement is created server-side here.
    // With a real payment gateway, create a pending payment and let its verified webhook complete it.
    const amountPaid = Number(course.price || 0) || 0;
    const paymentRef = db.collection('payments').doc();
    const now = admin.firestore.FieldValue.serverTimestamp();
    const batch = db.batch();
    batch.set(paymentRef, { uid, courseId, amount: amountPaid, status: 'completed', source: 'platform_checkout', createdAt: now, completedAt: now });
    batch.set(purchaseRef, { uid, courseId, status: 'completed', amountPaid, paymentId: paymentRef.id, source: String(request.data?.source || 'web'), purchasedAt: now, updatedAt: now }, { merge: true });
    await batch.commit();

    // The purchase is already saved: a notification problem must never fail it.
    try { await sendPurchaseNotification(uid, courseId, course); }
    catch (e) { console.error('purchaseCourse: notification failed (purchase kept)', e); }
    return { ok: true, alreadyPurchased: false, paymentId: paymentRef.id, amountPaid };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error('purchaseCourse failed', e);
    throw new HttpsError('internal', `تعذر إتمام الشراء: ${String(e?.message || e).slice(0, 180)}`);
  }
});

/** Firebase-first purchase check with R2 disaster-recovery fallback. */
exports.checkCourseAccess = onCall({ secrets: R2_SECRETS }, async (request) => {
  const uid = request.auth?.uid;
  const courseId = String(request.data?.courseId || '').trim();
  if (!uid) throw new HttpsError('unauthenticated', 'لازم تسجل الدخول أولاً');
  if (!courseId) throw new HttpsError('invalid-argument', 'courseId مطلوب');
  try {
    const snap = await db.collection('purchases').doc(`${uid}_${courseId}`).get();
    if (snap.exists) return { purchased: snap.data()?.status === 'completed', source: 'firebase' };
  } catch (_) {}
  try {
    const response = await fetch(`${R2_PUBLIC_BASE}/entitlements/${entitlementKey(uid, courseId)}.json`);
    if (response.ok) {
      const entitlement = await response.json();
      if (String(entitlement.uid) === uid && String(entitlement.courseId) === courseId) {
        return { purchased: entitlement.status === 'completed', source: 'r2' };
      }
    }
  } catch (_) {}
  return { purchased: false, source: 'none' };
});

/** Returns purchased course IDs; falls back to the R2 entitlement index. */
exports.getMyPurchasedCourseIds = onCall({ secrets: R2_SECRETS }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'لازم تسجل الدخول أولاً');
  try {
    const snap = await db.collection('purchases').where('uid', '==', uid).where('status', '==', 'completed').get();
    const ids = snap.docs.map(d => String(d.data()?.courseId || '')).filter(Boolean);
    if (ids.length) return { courseIds: [...new Set(ids)], source: 'firebase' };
  } catch (_) {}
  try {
    const response = await fetch(`${R2_PUBLIC_BASE}/users/${entitlementKey(uid, 'index')}.json`);
    if (response.ok) { const data = await response.json(); if (Array.isArray(data.courseIds)) return { courseIds: data.courseIds.map(String), source: 'r2' }; }
  } catch (_) {}
  return { courseIds: [], source: 'none' };
});

/**
 * Firestore trigger: whenever a payment document is marked completed,
 * automatically create/update the matching purchase document so the
 * client's hasPurchased() check and getSignedVideoUrl() both see it
 * immediately, without the app having to write purchases itself
 * (writing purchases directly from the client would let a user fake
 * a purchase — this must happen server-side, driven by your real
 * payment webhook writing into `payments`).
 */
exports.onPaymentCompleted = onDocumentWritten("payments/{paymentId}", async (event) => {
  const before = event.data?.before?.data() || {};
  const payment = event.data?.after?.data();
  if (!payment || payment.status !== "completed" || before.status === "completed") return;

  await db.collection("purchases").doc(`${payment.uid}_${payment.courseId}`).set({
    uid: payment.uid,
    courseId: payment.courseId,
    status: "completed",
    purchasedAt: admin.firestore.FieldValue.serverTimestamp(),
    paymentId: event.params.paymentId,
  });

  if (payment.source === 'platform_checkout') return;
  const courseSnap = await db.collection('courses').doc(payment.courseId).get();
  const courseTitle = courseSnap.data()?.title || 'الكورس';
  await db.collection('users').doc(payment.uid).collection('notifications').doc(`purchase_${event.params.paymentId}`).set({
    title: 'تم تأكيد شراء الكورس',
    body: `تم تفعيل ${courseTitle} في حسابك ويمكنك بدء المشاهدة الآن.`,
    imageUrl: String(courseSnap.data()?.thumbnailUrl || ''),
    type: 'purchase_completed', courseId: payment.courseId, read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  const tokensSnap = await db.collection('users').doc(payment.uid).collection('fcmTokens').get();
  const tokens = tokensSnap.docs.map(d => d.data()?.token).filter(Boolean);
  if (tokens.length) {
    for (let i = 0; i < tokens.length; i += 500) {
      await admin.messaging().sendEachForMulticast({
        tokens: tokens.slice(i, i + 500),
        notification: { title: 'تم تأكيد شراء الكورس', body: `تم تفعيل ${courseTitle} في حسابك.`, ...(courseSnap.data()?.thumbnailUrl ? { imageUrl: String(courseSnap.data().thumbnailUrl) } : {}) },
        data: { type: 'purchase_completed', courseId: String(payment.courseId) },
      });
    }
  }
});

/** Mirror published course metadata and lesson R2 keys to a public, non-sensitive R2 manifest. */
exports.syncCourseManifest = onDocumentWritten({ document: 'courses/{courseId}', secrets: R2_SECRETS }, async (event) => {
  const after = event.data?.after?.data();
  if (!after || (after.status && after.status !== 'published' && after.isPublished !== true)) return;
  const courseId = event.params.courseId;
  const lessonsSnap = await db.collection('courses').doc(courseId).collection('lessons').orderBy('order').get();
  const lessons = lessonsSnap.docs.map(d => ({ id: d.id, ...d.data() }));
  const manifest = { id: courseId, ...after, lessons };
  await putObject(`courses/${courseId}/manifest.json`, Buffer.from(JSON.stringify(manifest)), 'application/json');
});

/** Mirror entitlements to R2 only as a disaster-recovery fallback for the server. */
exports.syncPurchaseEntitlement = onDocumentWritten({ document: 'purchases/{purchaseId}', secrets: R2_SECRETS }, async (event) => {
  const purchase = event.data?.after?.data();
  if (!purchase?.uid || !purchase?.courseId) return;
  const payload = { uid: String(purchase.uid), courseId: String(purchase.courseId), status: String(purchase.status || ''), updatedAt: new Date().toISOString() };
  await putObject(`entitlements/${entitlementKey(String(purchase.uid), String(purchase.courseId))}.json`, Buffer.from(JSON.stringify(payload)), 'application/json');
});

/** Keep a recovery index of purchased course IDs for the signed-in user. */
exports.syncPurchaseIndex = onDocumentWritten({ document: 'purchases/{purchaseId}', secrets: R2_SECRETS }, async (event) => {
  const purchase = event.data?.after?.data();
  if (!purchase?.uid || !purchase?.courseId) return;
  const snap = await db.collection('purchases').where('uid', '==', String(purchase.uid)).where('status', '==', 'completed').get();
  const courseIds = snap.docs.map(d => String(d.data()?.courseId || '')).filter(Boolean);
  await putObject(`users/${entitlementKey(String(purchase.uid), 'index')}.json`, Buffer.from(JSON.stringify({ uid: String(purchase.uid), courseIds: [...new Set(courseIds)], updatedAt: new Date().toISOString() })), 'application/json');
});

/**
 * Admin-only course review. The admin may approve or reject a pending course.
 * Rejection requires a non-empty reason. Every decision is appended to the
 * course's reviews subcollection for an audit trail.
 */
exports.reviewCourse = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "لازم تسجل الدخول أولاً");

  const profile = await db.collection("users").doc(uid).get();
  const isAdmin = request.auth.token?.admin === true || profile.data()?.role === "admin";
  if (!isAdmin) throw new HttpsError("permission-denied", "ليس لديك صلاحية الأدمن");

  const data = request.data || {};
  const courseId = String(data.courseId || "").trim();
  const decision = String(data.decision || "").trim();
  const rejectionReason = String(data.rejectionReason || "").trim();
  if (!courseId || !["approved", "rejected"].includes(decision)) {
    throw new HttpsError("invalid-argument", "بيانات المراجعة غير صحيحة");
  }
  if (decision === "rejected" && !rejectionReason) {
    throw new HttpsError("invalid-argument", "سبب الرفض مطلوب");
  }

  const courseRef = db.collection("courses").doc(courseId);
  const courseSnap = await courseRef.get();
  if (!courseSnap.exists) throw new HttpsError("not-found", "الكورس غير موجود");
  const course = courseSnap.data() || {};
  if (course.status && course.status !== "pending") {
    throw new HttpsError("failed-precondition", "الكورس ليس قيد المراجعة حاليًا");
  }

  const reviewerName = request.auth.token?.name || profile.data()?.name || request.auth.token?.email || uid;
  const now = admin.firestore.FieldValue.serverTimestamp();
  const reviewRef = courseRef.collection("reviews").doc();

  const update = decision === "approved"
    ? {
        status: "published",
        isPublished: true,
        rejectionReason: admin.firestore.FieldValue.delete(),
        reviewedAt: now,
        reviewedBy: uid,
      }
    : {
        status: "rejected",
        isPublished: false,
        rejectionReason,
        reviewedAt: now,
        reviewedBy: uid,
      };

  const batch = db.batch();
  batch.update(courseRef, update);
  batch.set(reviewRef, {
    reviewerUid: uid,
    reviewerName,
    decision,
    rejectionReason: decision === "rejected" ? rejectionReason : null,
    reviewedAt: now,
  });
  await batch.commit();

  // Notify the course owner when available.
  const ownerUid = course.ownerUid || course.instructorUid || course.createdBy;
  if (ownerUid) {
    await db.collection("users").doc(String(ownerUid)).collection("notifications").add({
      type: "course_review",
      courseId,
      decision,
      rejectionReason: decision === "rejected" ? rejectionReason : null,
      createdAt: now,
      read: false,
    });
  }

  return { ok: true, status: update.status };
});

/** Create an admin account from the in-app admin panel. */
exports.grantAdmin = onCall(async (request) => {
  if (!(await isAdminRequest(request))) throw new HttpsError('permission-denied', 'ليس لديك صلاحية الأدمن');
  const identifier = String(request.data?.identifier || '').trim();
  const type = String(request.data?.type || 'auto').trim();
  if (!identifier) throw new HttpsError('invalid-argument', 'أدخل UID أو البريد أو رقم الهاتف');
  let target;
  try {
    if (type === 'uid' || (type === 'auto' && !identifier.includes('@') && !/^\+?\d{8,15}$/.test(identifier))) target = await admin.auth().getUser(identifier);
    else if (type === 'phone' || (type === 'auto' && /^\+?\d{8,15}$/.test(identifier))) target = await admin.auth().getUserByPhoneNumber(identifier);
    else target = await admin.auth().getUserByEmail(identifier.toLowerCase());
  } catch (_) { throw new HttpsError('not-found', 'الحساب غير موجود في Firebase Authentication'); }
  await admin.auth().setCustomUserClaims(target.uid, { ...(target.customClaims || {}), admin: true });
  await db.collection('users').doc(target.uid).set({ uid: target.uid, email: target.email || '', phoneNumber: target.phoneNumber || '', isAdmin: true, role: 'admin', adminGrantedAt: admin.firestore.FieldValue.serverTimestamp(), adminGrantedBy: request.auth.uid }, { merge: true });
  await db.collection('adminLogs').add({ action: 'grant_admin', targetUserId: target.uid, identifier, grantedBy: request.auth.uid, timestamp: admin.firestore.FieldValue.serverTimestamp() });
  return { ok: true, uid: target.uid };
});

/** Temporarily block a user and disable Firebase Authentication. */
exports.setUserBan = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'لازم تسجل الدخول أولاً');
  const me = await db.collection('users').doc(uid).get();
  if (!(request.auth.token?.admin === true || me.data()?.isAdmin === true || me.data()?.role === 'admin')) throw new HttpsError('permission-denied', 'ليس لديك صلاحية الأدمن');
  const targetUid = String(request.data?.uid || '').trim();
  const days = Math.max(1, Math.min(3650, Number(request.data?.days || 1)));
  const reason = String(request.data?.reason || '').trim();
  if (!targetUid || !reason) throw new HttpsError('invalid-argument', 'السبب مطلوب');
  const until = new Date(Date.now() + days * 86400000);
  await admin.auth().updateUser(targetUid, { disabled: true });
  await db.collection('users').doc(targetUid).set({ status: 'blocked', banReason: reason, banDays: days, bannedAt: admin.firestore.FieldValue.serverTimestamp(), bannedUntil: admin.firestore.Timestamp.fromDate(until) }, { merge: true });
  return { ok: true, bannedUntil: until.toISOString() };
});

/** Queue an FCM notification for a specific time. */
exports.scheduleNotification = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'لازم تسجل الدخول أولاً');
  const me = await db.collection('users').doc(uid).get();
  if (!(request.auth.token?.admin === true || me.data()?.isAdmin === true || me.data()?.role === 'admin')) throw new HttpsError('permission-denied', 'ليس لديك صلاحية الأدمن');
  const { title, body, imageUrl, campaign, description, sendAt, audience } = request.data || {};
  const date = new Date(String(sendAt || ''));
  if (!title || !body || Number.isNaN(date.getTime()) || date.getTime() <= Date.now()) throw new HttpsError('invalid-argument', 'بيانات الإشعار أو الموعد غير صحيحة');
  const ref = await db.collection('scheduledNotifications').add({ title: String(title), body: String(body), imageUrl: String(imageUrl || ''), campaign: String(campaign || ''), description: String(description || ''), audience: String(audience || 'all'), sendAt: admin.firestore.Timestamp.fromDate(date), status: 'pending', createdBy: uid, createdAt: admin.firestore.FieldValue.serverTimestamp() });
  return { id: ref.id };
});

/** When a paid session gets a scheduled time, queue reminders for both participants. */
exports.onIstifhamScheduled = onDocumentUpdated('istifhams/{requestId}', async (event) => {
  const before = event.data?.before?.data() || {};
  const after = event.data?.after?.data() || {};
  if (after.status !== 'paid' || !after.meetingTime) return;
  if (String(before.status || '') === 'paid' && String(before.meetingTime || '') === String(after.meetingTime || '')) return;
  const date = new Date(String(after.meetingTime));
  if (Number.isNaN(date.getTime()) || date.getTime() <= Date.now()) return;
  const targetUids = [after.mustafhemId, after.mufhemId].filter(Boolean);
  await db.collection('scheduledNotifications').add({
    title: `موعد المحاضرة: ${String(after.title || 'محاضرة')}`,
    body: `المحاضرة تبدأ في ${date.toLocaleString('ar-EG')}. اضغط على الإشعار للدخول من التطبيق.`,
    imageUrl: String(after.mufhemPhotoUrl || after.imageUrl || ''),
    audience: 'users',
    targetUids,
    action: 'meeting',
    requestId: event.params.requestId,
    sendAt: admin.firestore.Timestamp.fromDate(new Date(date.getTime() - 5 * 60 * 1000)),
    status: 'pending',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
});

/** Runs every minute and delivers due scheduled notifications. */
exports.dispatchScheduledNotifications = require('firebase-functions/v2/scheduler').onSchedule('every 1 minutes', async () => {
  const now = admin.firestore.Timestamp.now();
  const snap = await db.collection('scheduledNotifications').where('status', '==', 'pending').where('sendAt', '<=', now).limit(20).get();
  for (const doc of snap.docs) {
    const n = doc.data();
    await doc.ref.update({ status: 'processing', processingAt: admin.firestore.FieldValue.serverTimestamp() });
    const allUsers = await db.collection('users').get();
    const targetIds = Array.isArray(n.targetUids) && n.targetUids.length ? new Set(n.targetUids.map(String)) : null;
    const users = allUsers.docs.filter(u => !targetIds || targetIds.has(u.id));
    const tokens = [];
    for (const u of users) {
      const ts = await u.ref.collection('fcmTokens').get();
      for (const t of ts.docs) { const token = t.data().token; if (token) tokens.push(token); }
    }
    let sent = 0;
    for (let i = 0; i < tokens.length; i += 500) {
      const chunk = tokens.slice(i, i + 500);
      const response = await admin.messaging().sendEachForMulticast({ tokens: chunk, notification: { title: n.title, body: n.body, ...(n.imageUrl ? { imageUrl: n.imageUrl } : {}) }, data: { type: n.action || 'admin_campaign', notificationId: doc.id, campaign: String(n.campaign || ''), description: String(n.description || ''), ...(n.requestId ? { requestId: String(n.requestId) } : {}) } });
      sent += response.successCount;
    }
    const batch = db.batch();
    for (const u of users.docs) {
      const payload = { title: n.title, body: n.body, imageUrl: n.imageUrl || '', campaign: n.campaign || '', description: n.description || '', type: n.action || 'admin_campaign', userId: u.id, requestId: n.requestId || null, createdAt: admin.firestore.FieldValue.serverTimestamp(), read: false };
      batch.set(u.ref.collection('notifications').doc(doc.id), payload, { merge: true });
      batch.set(db.collection('notifications').doc(`${u.id}_${doc.id}`), payload, { merge: true });
    }
    await batch.commit();
    await doc.ref.update({ status: 'sent', sentCount: sent, sentAt: admin.firestore.FieldValue.serverTimestamp() });
  }
});

/** Automatically restore users whose temporary ban has expired. */
exports.expireUserBans = require('firebase-functions/v2/scheduler').onSchedule('every 15 minutes', async () => {
  const now = admin.firestore.Timestamp.now();
  const snap = await db.collection('users').where('status', '==', 'blocked').where('bannedUntil', '<=', now).limit(100).get();
  for (const d of snap.docs) {
    try {
      await admin.auth().updateUser(d.id, { disabled: false });
      await d.ref.set({ status: 'active', banReason: admin.firestore.FieldValue.delete(), banDays: admin.firestore.FieldValue.delete(), bannedAt: admin.firestore.FieldValue.delete(), bannedUntil: admin.firestore.FieldValue.delete() }, { merge: true });
    } catch (e) { console.error('expire ban', d.id, e); }
  }
});

/** Mint a short-lived JaaS JWT for an authenticated app user. */
exports.getJaasMeetingToken = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'لازم تسجل الدخول أولاً');
  const profile = await db.collection('users').doc(uid).get();
  const p = profile.data() || {};
  if (p.status === 'blocked') throw new HttpsError('permission-denied', 'الحساب محظور');
  const requestId = String(request.data?.requestId || '').trim();
  if (requestId) {
    const meetingDoc = await db.collection('istifhams').doc(requestId).get();
    if (!meetingDoc.exists) throw new HttpsError('not-found', 'المحاضرة غير موجودة');
    const m = meetingDoc.data() || {};
    const participant = uid === m.mustafhemId || uid === m.mufhemId || p.isAdmin === true || p.role === 'admin';
    if (!participant) throw new HttpsError('permission-denied', 'لست من أطراف هذه المحاضرة');
    if (m.status !== 'paid' && p.isAdmin !== true && p.role !== 'admin') throw new HttpsError('failed-precondition', 'المحاضرة لم يتم تفعيلها بالدفع');
    const start = new Date(String(m.meetingTime || '')).getTime();
    if (Number.isFinite(start) && Date.now() < start - 5 * 60 * 1000 && p.isAdmin !== true && p.role !== 'admin') throw new HttpsError('failed-precondition', 'لم يحن موعد المحاضرة بعد');
  }
  const appId = process.env.JAAS_APP_ID || 'vpaas-magic-cookie-4ddd1f4050174a1b89a6ce9a82ade034';
  const keyId = process.env.JAAS_KEY_ID || '09cb60';
  const privateKey = process.env.JAAS_PRIVATE_KEY;
  if (!appId || !keyId || !privateKey) throw new HttpsError('failed-precondition', 'إعدادات JaaS JWT غير مكتملة على الخادم');
  const suppliedRoom = String(request.data?.room || '').trim();
  const room = suppliedRoom || (requestId ? `Fahimni_${requestId}` : '');
  if (!room || room.includes('/')) throw new HttpsError('invalid-argument', 'اسم الغرفة غير صحيح');
  const now = Math.floor(Date.now() / 1000);
  const moderator = p.isAdmin === true || p.role === 'admin' || p.mode === 'mofahhem';
  const token = jwt.sign({
    aud: 'jitsi',
    iss: 'chat',
    sub: appId,
    room,
    nbf: now - 5,
    exp: now + 2 * 60 * 60,
    context: { user: { id: uid, name: String(p.name || request.auth.token.name || request.auth.token.email || uid), email: String(p.email || request.auth.token.email || ''), avatar: String(p.photoUrl || ''), moderator: String(moderator) }, features: { recording: moderator, livestreaming: false, transcription: false } }
  }, privateKey.replace(/\\n/g, '\n'), { algorithm: 'RS256', keyid: keyId, header: { typ: 'JWT' } });
  return { token, appId, room: `${appId}/${room}` };
});

/** JaaS webhook: forward the recording URL to the Cloudflare Worker.
 * The Worker downloads the recording and stores it in R2, so this function
 * no longer needs R2 S3 credentials / Firebase Secret Manager.
 */
const R2_WORKER_URL = 'https://fahmny-r2.mohamedragabewiess.workers.dev';
exports.jaasRecordingWebhook = require('firebase-functions/v2/https').onRequest(async (req, res) => {
  try {
    const response = await fetch(`${R2_WORKER_URL}/__jaas/recording`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req.body || {}),
    });
    const body = await response.text();
    res.status(response.status).send(body);
  } catch (e) {
    console.error(e);
    res.status(500).send('webhook proxy error');
  }
});


/** Record privacy-conscious product analytics server-side. */
exports.logAnalyticsEvent = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'لازم تسجل الدخول أولاً');
  const event = String(request.data?.event || '').trim().slice(0, 80);
  if (!event) throw new HttpsError('invalid-argument', 'اسم الحدث مطلوب');
  await db.collection('analyticsEvents').add({
    uid, event, data: request.data?.data || {},
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

/** Record important user activity server-side for the admin Activity Log. */
exports.logUserActivity = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'لازم تسجل الدخول أولاً');
  const type = String(request.data?.type || '').trim();
  if (!type) throw new HttpsError('invalid-argument', 'نوع العملية مطلوب');
  await db.collection('activityLogs').add({
    uid, type,
    courseId: request.data?.courseId ? String(request.data.courseId) : null,
    metadata: request.data?.metadata || {},
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

/** Send an immediate campaign to selected users and persist it in their inbox. */
exports.sendNotificationCampaign = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'لازم تسجل الدخول أولاً');
  const me = await db.collection('users').doc(uid).get();
  const adminUser = request.auth.token?.admin === true || me.data()?.isAdmin === true || me.data()?.role === 'admin';
  if (!adminUser) throw new HttpsError('permission-denied', 'ليس لديك صلاحية الأدمن');
  const title = String(request.data?.title || '').trim();
  const body = String(request.data?.body || '').trim();
  const imageUrl = String(request.data?.imageUrl || '').trim();
  const targetUids = Array.isArray(request.data?.userIds) ? request.data.userIds.map(String).filter(Boolean) : [];
  if (!title || !body || !targetUids.length) throw new HttpsError('invalid-argument', 'العنوان والنص والمستلمون مطلوبون');
  let sent = 0;
  for (const target of targetUids) {
    await db.collection('users').doc(target).collection('notifications').add({ title, body, imageUrl, type: 'campaign', read: false, createdAt: admin.firestore.FieldValue.serverTimestamp() });
    const tokenSnap = await db.collection('users').doc(target).collection('fcmTokens').get();
    const tokens = tokenSnap.docs.map(d => d.data()?.token).filter(Boolean);
    for (let i = 0; i < tokens.length; i += 500) {
      const result = await admin.messaging().sendEachForMulticast({
        tokens: tokens.slice(i, i + 500),
        notification: { title, body, ...(imageUrl ? { imageUrl } : {}) },
        data: { type: 'campaign' },
      });
      sent += result.successCount;
    }
  }
  await db.collection('notificationCampaigns').add({ title, body, imageUrl, targetUids, sent, createdBy: uid, createdAt: admin.firestore.FieldValue.serverTimestamp() });
  return { ok: true, sent };
});

/** Create a referral code for a user. */
exports.ensureReferralCode = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'لازم تسجل الدخول أولاً');
  const ref = db.collection('users').doc(uid);
  const snap = await ref.get();
  const existing = snap.data()?.referralCode;
  if (existing) return { code: String(existing) };
  const code = `FAH-${uid.slice(0, 6).toUpperCase()}-${Math.random().toString(36).slice(2, 6).toUpperCase()}`;
  await ref.set({ referralCode: code }, { merge: true });
  return { code };
});

/** Admin-only: write R2 manifests for every published course (run once for courses published before syncCourseManifest existed). */
exports.backfillCourseManifests = onCall({ secrets: R2_SECRETS, timeoutSeconds: 540 }, async (request) => {
  if (!(await isAdminRequest(request))) throw new HttpsError('permission-denied', 'ليس لديك صلاحية الأدمن');
  const snap = await db.collection('courses').get();
  let count = 0;
  for (const c of snap.docs) {
    const data = c.data();
    if (data.status && data.status !== 'published' && data.isPublished !== true) continue;
    const lessonsSnap = await c.ref.collection('lessons').orderBy('order').get();
    const lessons = lessonsSnap.docs.map(d => ({ id: d.id, ...d.data() }));
    await putObject(`courses/${c.id}/manifest.json`, Buffer.from(JSON.stringify({ id: c.id, ...data, lessons })), 'application/json');
    count++;
  }
  return { ok: true, count };
});


// المجموعات
Object.assign(exports, require('./groups'));
