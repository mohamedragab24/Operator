/**
 * المجموعات (Groups): الرقم التعريفي، الدعوات، الأعضاء، المحتوى، الجلسات، الفوترة الأسبوعية، التجميد والحذف.
 * كل الكتابة الحساسة هنا (Admin SDK) — القواعد تمنع العميل من الكتابة المباشرة.
 */
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { presignedUrl, deleteObject } = require('./r2');

const db = admin.firestore();
const FV = admin.firestore.FieldValue;
const TS = admin.firestore.Timestamp;
const R2_SECRETS = ['R2_ACCOUNT_ID', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY', 'R2_BUCKET'];

const PRICE_PER_GB_WEEK = 5;       // جنيه / جيجا / أسبوع
const PRICE_PER_STUDENT_WEEK = 10; // جنيه / مستفهم / أسبوع
const MIN_PREPAID = 100;           // أقل رصيد لإضافة طلاب بعد رفع محتوى
const FREEZE_AFTER_HOURS = 48;
const PURGE_AFTER_DAYS = 7;
const GB = 1024 * 1024 * 1024;
const CONTENT_KINDS = ['videos', 'files', 'quizzes'];
const TZ = 'Africa/Cairo';

const round2 = (n) => Math.round((Number(n) || 0) * 100) / 100;
const reqUid = (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'لازم تسجل الدخول أولاً');
  return uid;
};

// ---------------------------------------------------------------- الرقم التعريفي
const ID_CHARS = '0123456789abcdefghijklmnopqrstuvwxyz';
const randomPublicId = () => Array.from({ length: 8 }, () => ID_CHARS[crypto.randomInt(ID_CHARS.length)]).join('');

async function ensurePublicIdFor(uid) {
  return db.runTransaction(async (t) => {
    const userRef = db.collection('users').doc(uid);
    const userSnap = await t.get(userRef);
    const existing = userSnap.exists ? userSnap.data()?.publicId : null;
    if (existing) return String(existing);
    const candidates = Array.from({ length: 6 }, randomPublicId);
    const refs = candidates.map((c) => db.collection('publicIds').doc(c));
    const snaps = await Promise.all(refs.map((r) => t.get(r)));
    const idx = snaps.findIndex((s) => !s.exists);
    if (idx < 0) throw new HttpsError('aborted', 'تعذر توليد رقم تعريفي، حاول مرة أخرى');
    t.set(refs[idx], { uid, createdAt: FV.serverTimestamp() });
    t.set(userRef, { publicId: candidates[idx] }, { merge: true });
    return candidates[idx];
  });
}

exports.ensurePublicId = onCall(async (request) => {
  const uid = reqUid(request);
  return { publicId: await ensurePublicIdFor(uid) };
});

exports.assignPublicIdOnSignup = onDocumentCreated('users/{uid}', async (event) => {
  if (event.data?.data()?.publicId) return;
  await ensurePublicIdFor(event.params.uid);
});

/** للأدمن: توليد رقم تعريفي لكل من لا يملكه. */
exports.backfillPublicIds = onCall({ timeoutSeconds: 540 }, async (request) => {
  const uid = reqUid(request);
  const me = (await db.collection('users').doc(uid).get()).data() || {};
  if (!(me.isAdmin === true || me.role === 'admin')) throw new HttpsError('permission-denied', 'للأدمن فقط');
  const users = await db.collection('users').get();
  let n = 0;
  for (const u of users.docs) {
    if (u.data()?.publicId) continue;
    try { await ensurePublicIdFor(u.id); n++; } catch (e) { console.error('backfill', u.id, e); }
  }
  return { ok: true, assigned: n };
});

// ---------------------------------------------------------------- مساعدات
async function isAdminUid(uid) {
  const p = (await db.collection('users').doc(uid).get()).data() || {};
  return p.isAdmin === true || p.role === 'admin';
}

async function loadOwnedGroup(uid, groupId, { requireActive = true } = {}) {
  const id = String(groupId || '').trim();
  if (!id) throw new HttpsError('invalid-argument', 'معرف المجموعة غير صحيح');
  const ref = db.collection('groups').doc(id);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'المجموعة غير موجودة');
  const g = snap.data() || {};
  if (g.ownerUid !== uid && !(await isAdminUid(uid))) throw new HttpsError('permission-denied', 'هذه المجموعة ليست مجموعتك');
  if (requireActive && g.status === 'frozen') throw new HttpsError('failed-precondition', 'المجموعة مجمّدة بسبب رسوم غير مدفوعة');
  return { ref, g, id };
}

async function walletBalance(uid) {
  const snap = await db.collection('users').doc(uid).collection('transactions').get();
  let b = 0;
  snap.forEach((d) => {
    const tx = d.data() || {};
    const amount = Number(tx.amount || 0);
    if (tx.status === 'rejected') return;
    if (tx.type === 'deposit' || tx.type === 'earning') { if (tx.status !== 'pending') b += amount; }
    else b -= amount;
  });
  return round2(b);
}

async function chargeWallet(uid, amount, description, extra = {}) {
  await db.collection('users').doc(uid).collection('transactions').add({
    type: 'group_fee', amount: round2(amount), status: 'completed', description,
    timestamp: FV.serverTimestamp(), ...extra,
  });
}

async function notify(uid, title, body, extra = {}, docId) {
  try {
    const col = db.collection('users').doc(uid).collection('notifications');
    const data = { title, body, read: false, createdAt: FV.serverTimestamp(), ...extra };
    if (docId) await col.doc(docId).set(data, { merge: true }); else await col.add(data);
  } catch (e) { console.error('notify failed', e); }
}

async function collectR2Keys(groupRef) {
  const keys = [];
  for (const col of ['videos', 'files', 'recordings']) {
    const s = await groupRef.collection(col).get();
    s.forEach((d) => { const k = d.data()?.r2Key; if (k) keys.push(String(k)); });
  }
  return keys;
}

/** حذف نهائي: ملفات R2 + كل المستندات + عضويات الطلاب + الدعوات. */
async function purgeGroup(groupId) {
  const ref = db.collection('groups').doc(groupId);
  const keys = await collectR2Keys(ref).catch(() => []);
  for (const k of keys) { try { await deleteObject(k); } catch (e) { console.error('r2 delete', k, e); } }
  const members = await ref.collection('members').get();
  for (const m of members.docs) {
    try { await db.collection('users').doc(m.id).collection('groupMemberships').doc(groupId).delete(); } catch (_) {}
  }
  const invites = await db.collection('groupInvites').where('groupId', '==', groupId).get();
  for (const i of invites.docs) { try { await i.ref.delete(); } catch (_) {} }
  await db.recursiveDelete(ref);
}

// ---------------------------------------------------------------- المجموعات
exports.createGroup = onCall(async (request) => {
  const uid = reqUid(request);
  const me = (await db.collection('users').doc(uid).get()).data() || {};
  if (!(me.role === 'mufhem' || me.isAdmin === true)) throw new HttpsError('permission-denied', 'إنشاء المجموعات للمُفهمين فقط');
  const name = String(request.data?.name || '').trim();
  const description = String(request.data?.description || '').trim().slice(0, 500);
  if (name.length < 3 || name.length > 80) throw new HttpsError('invalid-argument', 'اسم المجموعة من 3 إلى 80 حرفًا');
  const ref = db.collection('groups').doc();
  await ref.set({
    name, description, ownerUid: uid, ownerName: String(me.name || me.fullName || ''),
    status: 'active', memberCount: 0, storageBytes: 0, contentCount: 0,
    createdAt: FV.serverTimestamp(),
  });
  return { ok: true, groupId: ref.id };
});

exports.sendGroupInvite = onCall(async (request) => {
  const uid = reqUid(request);
  const { ref, g, id } = await loadOwnedGroup(uid, request.data?.groupId);
  const publicId = String(request.data?.publicId || '').trim().toLowerCase();
  if (!/^[0-9a-z]{8}$/.test(publicId)) throw new HttpsError('invalid-argument', 'الرقم التعريفي يتكون من 8 أرقام/حروف إنجليزية');
  const idSnap = await db.collection('publicIds').doc(publicId).get();
  if (!idSnap.exists) throw new HttpsError('not-found', 'لا يوجد مستخدم بهذا الرقم التعريفي');
  const toUid = String(idSnap.data().uid);
  if (toUid === g.ownerUid) throw new HttpsError('invalid-argument', 'لا يمكنك دعوة نفسك');
  if ((await ref.collection('members').doc(toUid).get()).exists) throw new HttpsError('already-exists', 'الطالب عضو بالفعل');

  // بعد رفع محتوى: لازم رصيد 100 جنيه على الأقل لإضافة طلاب.
  if (Number(g.contentCount || 0) > 0 || Number(g.storageBytes || 0) > 0) {
    const balance = await walletBalance(g.ownerUid);
    if (balance < MIN_PREPAID) {
      throw new HttpsError('failed-precondition', `لإضافة طلاب بعد رفع المحتوى اشحن رصيدك ${MIN_PREPAID} جنيه على الأقل (رصيدك ${balance} جنيه)`);
    }
  }
  const toUser = (await db.collection('users').doc(toUid).get()).data() || {};
  const inviteRef = db.collection('groupInvites').doc(`${id}_${toUid}`);
  await inviteRef.set({
    groupId: id, groupName: g.name, ownerUid: g.ownerUid, ownerName: g.ownerName || '',
    toUid, toPublicId: publicId, toName: String(toUser.name || toUser.fullName || ''),
    status: 'pending', createdAt: FV.serverTimestamp(),
  });
  await notify(toUid, 'دعوة للانضمام إلى مجموعة', `${g.ownerName || 'مُفهم'} يدعوك للانضمام إلى مجموعة «${g.name}»`, { type: 'group_invite', groupId: id }, `ginvite_${id}`);
  return { ok: true, toName: String(toUser.name || toUser.fullName || '') };
});

exports.respondGroupInvite = onCall(async (request) => {
  const uid = reqUid(request);
  const inviteId = String(request.data?.inviteId || '').trim();
  const accept = request.data?.accept === true;
  const inviteRef = db.collection('groupInvites').doc(inviteId);
  const invite = await inviteRef.get();
  if (!invite.exists) throw new HttpsError('not-found', 'الدعوة غير موجودة');
  const inv = invite.data();
  if (inv.toUid !== uid) throw new HttpsError('permission-denied', 'هذه الدعوة ليست لك');
  if (inv.status !== 'pending') throw new HttpsError('failed-precondition', 'تم الرد على هذه الدعوة من قبل');
  if (!accept) { await inviteRef.update({ status: 'declined', respondedAt: FV.serverTimestamp() }); return { ok: true, joined: false }; }

  const groupRef = db.collection('groups').doc(inv.groupId);
  const me = (await db.collection('users').doc(uid).get()).data() || {};
  await db.runTransaction(async (t) => {
    const gs = await t.get(groupRef);
    if (!gs.exists) throw new HttpsError('not-found', 'المجموعة لم تعد موجودة');
    if (gs.data().status === 'frozen') throw new HttpsError('failed-precondition', 'المجموعة متوقفة مؤقتًا');
    const memberRef = groupRef.collection('members').doc(uid);
    const ms = await t.get(memberRef);
    if (!ms.exists) {
      t.set(memberRef, { uid, name: String(me.name || me.fullName || ''), publicId: String(me.publicId || inv.toPublicId || ''), joinedAt: FV.serverTimestamp() });
      t.update(groupRef, { memberCount: FV.increment(1) });
    }
    t.set(db.collection('users').doc(uid).collection('groupMemberships').doc(inv.groupId), { groupId: inv.groupId, groupName: inv.groupName, ownerUid: inv.ownerUid, joinedAt: FV.serverTimestamp() });
    t.update(inviteRef, { status: 'accepted', respondedAt: FV.serverTimestamp() });
  });
  await notify(inv.ownerUid, 'انضم طالب إلى مجموعتك', `${String(me.name || me.fullName || 'طالب')} انضم إلى «${inv.groupName}»`, { type: 'group_joined', groupId: inv.groupId });
  return { ok: true, joined: true, groupId: inv.groupId };
});

exports.removeGroupMember = onCall(async (request) => {
  const uid = reqUid(request);
  const { ref, id } = await loadOwnedGroup(uid, request.data?.groupId, { requireActive: false });
  const memberUid = String(request.data?.uid || '').trim();
  if (!memberUid) throw new HttpsError('invalid-argument', 'الطالب غير محدد');
  await db.runTransaction(async (t) => {
    const memberRef = ref.collection('members').doc(memberUid);
    const ms = await t.get(memberRef);
    if (ms.exists) { t.delete(memberRef); t.update(ref, { memberCount: FV.increment(-1) }); }
    t.delete(db.collection('users').doc(memberUid).collection('groupMemberships').doc(id));
    t.delete(db.collection('groupInvites').doc(`${id}_${memberUid}`));
  });
  return { ok: true };
});

/** إنهاء المجموعة وحذفها نهائيًا. يتطلب تسجيل دخول حديث (خلال 5 دقائق) للتأكد أن الحساب حساب صاحبه. */
exports.deleteGroup = onCall({ secrets: R2_SECRETS, timeoutSeconds: 540 }, async (request) => {
  const uid = reqUid(request);
  const { id, g } = await loadOwnedGroup(uid, request.data?.groupId, { requireActive: false });
  const authTime = Number(request.auth?.token?.auth_time || 0);
  if (!authTime || Date.now() / 1000 - authTime > 300) {
    throw new HttpsError('failed-precondition', 'REAUTH_REQUIRED');
  }
  if (String(request.data?.confirmName || '').trim() !== String(g.name || '')) {
    throw new HttpsError('invalid-argument', 'اكتب اسم المجموعة بالضبط لتأكيد الحذف');
  }
  await purgeGroup(id);
  return { ok: true };
});

// ---------------------------------------------------------------- المحتوى
exports.registerGroupContent = onCall(async (request) => {
  const uid = reqUid(request);
  const { ref, id } = await loadOwnedGroup(uid, request.data?.groupId);
  const kind = String(request.data?.kind || '');
  if (!['videos', 'files'].includes(kind)) throw new HttpsError('invalid-argument', 'نوع المحتوى غير صحيح');
  const title = String(request.data?.title || '').trim().slice(0, 120);
  const r2Key = String(request.data?.r2Key || '').trim();
  const size = Math.max(0, Math.floor(Number(request.data?.size || 0)));
  if (!title) throw new HttpsError('invalid-argument', 'اكتب عنوانًا للمحتوى');
  if (!r2Key.startsWith(`groups/${id}/`) || r2Key.includes('..')) throw new HttpsError('invalid-argument', 'مسار الملف غير صحيح');
  const doc = ref.collection(kind).doc();
  await db.runTransaction(async (t) => {
    t.set(doc, { title, r2Key, size, contentType: String(request.data?.contentType || ''), createdAt: FV.serverTimestamp(), order: Date.now() });
    t.update(ref, { storageBytes: FV.increment(size), contentCount: FV.increment(1) });
  });
  return { ok: true, id: doc.id };
});

exports.createGroupQuiz = onCall(async (request) => {
  const uid = reqUid(request);
  const { ref } = await loadOwnedGroup(uid, request.data?.groupId);
  const title = String(request.data?.title || '').trim().slice(0, 120);
  const questions = Array.isArray(request.data?.questions) ? request.data.questions : [];
  if (!title || questions.length < 1 || questions.length > 100) throw new HttpsError('invalid-argument', 'الاختبار يحتاج عنوانًا وسؤالًا واحدًا على الأقل');
  const clean = questions.map((q, i) => {
    const type = q?.type === 'essay' ? 'essay' : 'mcq';
    const text = String(q?.text || '').trim().slice(0, 1000);
    if (!text) throw new HttpsError('invalid-argument', `السؤال ${i + 1} فارغ`);
    const points = Math.max(1, Math.min(100, Number(q?.points) || 1));
    if (type === 'essay') return { type, text, points };
    const options = (Array.isArray(q?.options) ? q.options : []).map((o) => String(o || '').trim().slice(0, 300)).filter(Boolean);
    const correct = Number(q?.correct);
    if (options.length < 2 || !Number.isInteger(correct) || correct < 0 || correct >= options.length) throw new HttpsError('invalid-argument', `السؤال ${i + 1}: اختيارات أو إجابة صحيحة غير صحيحة`);
    return { type, text, options, correct, points };
  });
  const doc = ref.collection('quizzes').doc();
  await db.runTransaction(async (t) => {
    t.set(doc, { title, questions: clean, questionCount: clean.length, hasEssay: clean.some((q) => q.type === 'essay'), createdAt: FV.serverTimestamp(), order: Date.now() });
    t.update(ref, { contentCount: FV.increment(1) });
  });
  return { ok: true, id: doc.id };
});

exports.deleteGroupContent = onCall({ secrets: R2_SECRETS }, async (request) => {
  const uid = reqUid(request);
  const { ref } = await loadOwnedGroup(uid, request.data?.groupId);
  const kind = String(request.data?.kind || '');
  if (![...CONTENT_KINDS, 'recordings'].includes(kind)) throw new HttpsError('invalid-argument', 'نوع المحتوى غير صحيح');
  const docRef = ref.collection(kind).doc(String(request.data?.id || ''));
  const snap = await docRef.get();
  if (!snap.exists) throw new HttpsError('not-found', 'المحتوى غير موجود');
  const d = snap.data() || {};
  if (d.r2Key) { try { await deleteObject(String(d.r2Key)); } catch (e) { console.error('r2 delete', e); } }
  await docRef.delete();
  await ref.update({ storageBytes: FV.increment(-Number(d.size || 0)), contentCount: FV.increment(-1) });
  return { ok: true };
});

/** رابط مشاهدة مؤقت — للتطبيق فقط. المنصة (الويب) لا تستدعيه. */
exports.getGroupMediaUrl = onCall({ secrets: R2_SECRETS }, async (request) => {
  const uid = reqUid(request);
  const groupId = String(request.data?.groupId || '').trim();
  const kind = String(request.data?.kind || '');
  if (!['videos', 'files', 'recordings'].includes(kind)) throw new HttpsError('invalid-argument', 'نوع المحتوى غير صحيح');
  const gs = await db.collection('groups').doc(groupId).get();
  if (!gs.exists) throw new HttpsError('not-found', 'المجموعة غير موجودة');
  const g = gs.data();
  if (g.status !== 'active') throw new HttpsError('failed-precondition', 'المجموعة متوقفة مؤقتًا');
  const isOwner = g.ownerUid === uid;
  if (!isOwner && !(await isAdminUid(uid))) {
    const m = await gs.ref.collection('members').doc(uid).get();
    if (!m.exists) throw new HttpsError('permission-denied', 'لست عضوًا في هذه المجموعة');
  }
  const item = await gs.ref.collection(kind).doc(String(request.data?.id || '')).get();
  if (!item.exists || !item.data()?.r2Key) throw new HttpsError('not-found', 'المحتوى غير موجود');
  const signed = presignedUrl({ method: 'GET', key: String(item.data().r2Key), expiresSeconds: 600 });
  const me = (await db.collection('users').doc(uid).get()).data() || {};
  return { ...signed, watermark: { uid, name: String(me.name || me.fullName || ''), publicId: String(me.publicId || '') } };
});

/** تصحيح تلقائي للاختياري؛ المقالي يبقى "بانتظار مراجعة المُفهم". يستدعيه التطبيق. */
exports.submitGroupQuiz = onCall(async (request) => {
  const uid = reqUid(request);
  const groupId = String(request.data?.groupId || '').trim();
  const quizId = String(request.data?.quizId || '').trim();
  const gs = await db.collection('groups').doc(groupId).get();
  if (!gs.exists || gs.data().status !== 'active') throw new HttpsError('failed-precondition', 'المجموعة غير متاحة');
  const member = await gs.ref.collection('members').doc(uid).get();
  if (!member.exists) throw new HttpsError('permission-denied', 'لست عضوًا في هذه المجموعة');
  const quizSnap = await gs.ref.collection('quizzes').doc(quizId).get();
  if (!quizSnap.exists) throw new HttpsError('not-found', 'الاختبار غير موجود');
  const subRef = quizSnap.ref.collection('submissions').doc(uid);
  if ((await subRef.get()).exists) throw new HttpsError('already-exists', 'سبق أن أرسلت هذا الاختبار');
  const quiz = quizSnap.data();
  const answers = Array.isArray(request.data?.answers) ? request.data.answers : [];
  let autoScore = 0, autoMax = 0, essayMax = 0;
  quiz.questions.forEach((q, i) => {
    if (q.type === 'mcq') { autoMax += q.points; if (Number(answers[i]) === q.correct) autoScore += q.points; }
    else essayMax += q.points;
  });
  const me = (await db.collection('users').doc(uid).get()).data() || {};
  await subRef.set({
    uid, name: String(me.name || me.fullName || ''), answers: answers.map((a) => (typeof a === 'string' ? a.slice(0, 5000) : Number(a))),
    autoScore, autoMax, essayMax, essayScore: null,
    status: quiz.hasEssay ? 'pending_review' : 'graded', submittedAt: FV.serverTimestamp(),
  });
  return { ok: true, autoScore, autoMax, pendingReview: !!quiz.hasEssay };
});

// ---------------------------------------------------------------- الجلسات
exports.startGroupSession = onCall(async (request) => {
  const uid = reqUid(request);
  const { ref, g, id } = await loadOwnedGroup(uid, request.data?.groupId);
  const record = request.data?.record === true;
  const title = String(request.data?.title || '').trim().slice(0, 120) || `جلسة ${new Date().toLocaleDateString('ar-EG', { timeZone: TZ })}`;
  const doc = ref.collection('sessions').doc();
  await doc.set({ title, record, status: 'live', startedAt: FV.serverTimestamp(), room: `Fahimni_group_${id}_${doc.id}` });
  const members = await ref.collection('members').get();
  for (const m of members.docs) await notify(m.id, 'بدأت جلسة جديدة', `بدأ المُفهم جلسة في «${g.name}» — ادخل من التطبيق`, { type: 'group_session', groupId: id, sessionId: doc.id }, `gsession_${doc.id}`);
  return { ok: true, sessionId: doc.id, room: `Fahimni_group_${id}_${doc.id}` };
});

exports.endGroupSession = onCall(async (request) => {
  const uid = reqUid(request);
  const { ref } = await loadOwnedGroup(uid, request.data?.groupId, { requireActive: false });
  const sid = String(request.data?.sessionId || '').trim();
  const sRef = ref.collection('sessions').doc(sid);
  const s = await sRef.get();
  if (!s.exists) throw new HttpsError('not-found', 'الجلسة غير موجودة');
  const d = s.data();
  await sRef.update({ status: 'ended', endedAt: FV.serverTimestamp() });
  if (d.record) {
    // يُضاف تلقائيًا لقسم الجلسات المسجلة؛ يكتمل الملف عند وصول تسجيل JaaS (webhook).
    await ref.collection('recordings').doc(sid).set({ title: d.title, sessionId: sid, status: 'processing', size: 0, createdAt: FV.serverTimestamp(), order: Date.now() }, { merge: true });
  }
  return { ok: true, recording: !!d.record };
});

exports.attachGroupRecording = onCall(async (request) => {
  const uid = reqUid(request);
  const { ref, id } = await loadOwnedGroup(uid, request.data?.groupId, { requireActive: false });
  const sid = String(request.data?.sessionId || '').trim();
  const r2Key = String(request.data?.r2Key || '').trim();
  const size = Math.max(0, Math.floor(Number(request.data?.size || 0)));
  if (!r2Key.startsWith(`groups/${id}/`) || r2Key.includes('..')) throw new HttpsError('invalid-argument', 'مسار الملف غير صحيح');
  const rRef = ref.collection('recordings').doc(sid);
  if (!(await rRef.get()).exists) throw new HttpsError('not-found', 'التسجيل غير موجود');
  await rRef.update({ r2Key, size, status: 'ready' });
  await ref.update({ storageBytes: FV.increment(size) });
  return { ok: true };
});

exports.getGroupMeetingToken = onCall(async (request) => {
  const uid = reqUid(request);
  const groupId = String(request.data?.groupId || '').trim();
  const sessionId = String(request.data?.sessionId || '').trim();
  const gs = await db.collection('groups').doc(groupId).get();
  if (!gs.exists) throw new HttpsError('not-found', 'المجموعة غير موجودة');
  const g = gs.data();
  if (g.status !== 'active') throw new HttpsError('failed-precondition', 'المجموعة متوقفة مؤقتًا');
  const isOwner = g.ownerUid === uid;
  if (!isOwner && !(await isAdminUid(uid))) {
    if (!(await gs.ref.collection('members').doc(uid).get()).exists) throw new HttpsError('permission-denied', 'الجلسة لأعضاء المجموعة فقط');
  }
  const ss = await gs.ref.collection('sessions').doc(sessionId).get();
  if (!ss.exists || ss.data().status !== 'live') throw new HttpsError('failed-precondition', 'الجلسة غير متاحة الآن');
  const appId = process.env.JAAS_APP_ID || 'vpaas-magic-cookie-4ddd1f4050174a1b89a6ce9a82ade034';
  const keyId = process.env.JAAS_KEY_ID || '09cb60';
  const privateKey = process.env.JAAS_PRIVATE_KEY;
  if (!privateKey) throw new HttpsError('failed-precondition', 'إعدادات JaaS JWT غير مكتملة على الخادم');
  const room = String(ss.data().room);
  const me = (await db.collection('users').doc(uid).get()).data() || {};
  const now = Math.floor(Date.now() / 1000);
  const token = jwt.sign({
    aud: 'jitsi', iss: 'chat', sub: appId, room, nbf: now - 5, exp: now + 3 * 60 * 60,
    context: {
      user: { id: uid, name: String(me.name || me.fullName || uid), email: String(me.email || ''), avatar: String(me.photoUrl || ''), moderator: String(isOwner) },
      features: { recording: String(isOwner && ss.data().record === true), livestreaming: 'false', transcription: 'false', 'outbound-call': 'false', 'sip-outbound-call': 'false' },
    },
  }, privateKey.replace(/\\n/g, '\n'), { algorithm: 'RS256', keyid: keyId, header: { typ: 'JWT' } });
  return { token, appId, room: `${appId}/${room}`, moderator: isOwner, record: ss.data().record === true };
});

/** رابط رفع مؤقت (PUT) مباشر إلى R2 — للمُفهم صاحب المجموعة فقط. */
exports.createGroupUploadUrl = onCall({ secrets: R2_SECRETS }, async (request) => {
  const uid = reqUid(request);
  const { id } = await loadOwnedGroup(uid, request.data?.groupId);
  const kind = String(request.data?.kind || '');
  if (!['videos', 'files'].includes(kind)) throw new HttpsError('invalid-argument', 'نوع المحتوى غير صحيح');
  const contentType = String(request.data?.contentType || 'application/octet-stream');
  if (kind === 'files' && contentType !== 'application/pdf') throw new HttpsError('invalid-argument', 'الملفات يجب أن تكون PDF');
  if (kind === 'videos' && !contentType.startsWith('video/')) throw new HttpsError('invalid-argument', 'الملف يجب أن يكون فيديو');
  const size = Number(request.data?.size || 0);
  if (size > 5 * GB) throw new HttpsError('invalid-argument', 'الحد الأقصى للملف 5 جيجا');
  const safe = String(request.data?.fileName || 'file').replace(/[^a-zA-Z0-9._-]/g, '_').slice(-120) || 'file';
  const key = `groups/${id}/${kind}/${Date.now()}_${crypto.randomBytes(3).toString('hex')}_${safe}`;
  const signed = presignedUrl({ method: 'PUT', key, expiresSeconds: 3600, contentType });
  return { ...signed, key };
});

// ---------------------------------------------------------------- الفوترة الأسبوعية
const cairoParts = (d = new Date()) => {
  const f = new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', hour12: false });
  const o = Object.fromEntries(f.formatToParts(d).map((p) => [p.type, p.value]));
  return { date: `${o.year}-${o.month}-${o.day}`, hour: o.hour };
};

/** عيّنة استخدام كل 6 ساعات: عدد الطلاب + حجم المحتوى. */
exports.groupUsageSnapshot = onSchedule({ schedule: 'every 6 hours', timeZone: TZ }, async () => {
  const { date, hour } = cairoParts();
  const groups = await db.collection('groups').where('status', '==', 'active').get();
  for (const g of groups.docs) {
    const d = g.data();
    await g.ref.collection('usage').doc(`${date}_${hour}`).set({ students: Number(d.memberCount || 0), bytes: Number(d.storageBytes || 0), at: FV.serverTimestamp(), day: date });
  }
});

async function settleOwnerBills(ownerUid) {
  const bills = await db.collection('groupBills').where('ownerUid', '==', ownerUid).where('status', '==', 'unpaid').get();
  if (bills.empty) return { paid: 0, remaining: 0, groups: [] };
  const sorted = bills.docs.sort((a, b) => (a.data().createdAt?.toMillis?.() || 0) - (b.data().createdAt?.toMillis?.() || 0));
  let balance = await walletBalance(ownerUid);
  let paid = 0, remaining = 0;
  const groups = new Set();
  for (const b of sorted) {
    const d = b.data();
    groups.add(d.groupId);
    if (balance >= d.fee) {
      await chargeWallet(ownerUid, d.fee, `رسوم مجموعة «${d.groupName}» — أسبوع ${d.weekKey}`, { groupId: d.groupId, billId: b.id });
      await b.ref.update({ status: 'paid', paidAt: FV.serverTimestamp() });
      balance = round2(balance - d.fee); paid++;
    } else remaining++;
  }
  return { paid, remaining, groups: [...groups] };
}

/** لو مفيش فواتير غير مدفوعة للمجموعة: ارفع التنبيه وأعِد تفعيلها (قبل انتهاء 7 أيام). */
async function refreshGroupBillingState(groupId) {
  const ref = db.collection('groups').doc(groupId);
  const snap = await ref.get();
  if (!snap.exists) return;
  const g = snap.data();
  const open = await db.collection('groupBills').where('groupId', '==', groupId).where('status', '==', 'unpaid').limit(1).get();
  if (!open.empty) return;
  const purgeMs = g.purgeAt?.toMillis?.() || 0;
  if (g.status === 'frozen' && purgeMs && purgeMs < Date.now()) return;
  if (g.freezeAt || g.status === 'frozen') {
    await ref.update({ status: 'active', freezeAt: FV.delete(), frozenAt: FV.delete(), purgeAt: FV.delete() });
    await notify(g.ownerUid, 'تم تفعيل مجموعتك', `تم سداد الرسوم وعادت المجموعة «${g.name}» للعمل.`, { type: 'group_active', groupId }, `gactive_${groupId}_${Date.now()}`);
  }
}

exports.groupWeeklyBilling = onSchedule({ schedule: 'every monday 03:00', timeZone: TZ }, async () => {
  const end = new Date();
  const since = new Date(end.getTime() - 7 * 24 * 3600 * 1000);
  const weekKey = cairoParts(end).date;
  const groups = await db.collection('groups').where('status', '==', 'active').get();
  const owners = new Set();
  for (const g of groups.docs) {
    const d = g.data();
    const usage = await g.ref.collection('usage').where('at', '>=', TS.fromDate(since)).get();
    let students = 0, bytes = 0, n = 0;
    usage.forEach((u) => { students += Number(u.data().students || 0); bytes += Number(u.data().bytes || 0); n++; });
    const avgStudents = n ? students / n : Number(d.memberCount || 0);
    const avgGB = (n ? bytes / n : Number(d.storageBytes || 0)) / GB;
    const fee = round2(avgGB * PRICE_PER_GB_WEEK + avgStudents * PRICE_PER_STUDENT_WEEK);
    const billRef = db.collection('groupBills').doc(`${g.id}_${weekKey}`);
    if ((await billRef.get()).exists) continue;
    await billRef.set({
      groupId: g.id, groupName: d.name, ownerUid: d.ownerUid, weekKey, samples: n,
      avgStudents: round2(avgStudents), avgGB: Math.round(avgGB * 1000) / 1000, fee,
      pricePerGB: PRICE_PER_GB_WEEK, pricePerStudent: PRICE_PER_STUDENT_WEEK,
      status: fee > 0 ? 'unpaid' : 'paid', createdAt: FV.serverTimestamp(),
    });
    if (fee > 0) owners.add(d.ownerUid);
  }
  for (const ownerUid of owners) {
    const r = await settleOwnerBills(ownerUid);
    const mine = groups.docs.filter((g) => g.data().ownerUid === ownerUid);
    for (const g of mine) {
      const open = await db.collection('groupBills').where('groupId', '==', g.id).where('status', '==', 'unpaid').limit(1).get();
      if (open.empty) continue;
      const freezeAt = TS.fromMillis(Date.now() + FREEZE_AFTER_HOURS * 3600 * 1000);
      if (!g.data().freezeAt) await g.ref.update({ freezeAt });
      await notify(ownerUid, 'يجب شحن رصيدك', `رصيدك لا يكفي رسوم مجموعة «${g.data().name}». اشحن رصيدك خلال يومين وإلا سيتم تجميد المجموعة.`, { type: 'group_payment_due', groupId: g.id }, `gdue_${g.id}_${weekKey}`);
    }
    if (!r.remaining) for (const gid of r.groups) await refreshGroupBillingState(gid);
  }
});

/** تنبيه مسبق (السبت والأحد) لو الرصيد لا يكفي تقدير رسوم الأسبوع. */
exports.groupBalanceWarnings = onSchedule({ schedule: 'every day 12:00', timeZone: TZ }, async () => {
  const dow = new Date(new Date().toLocaleString('en-US', { timeZone: TZ })).getDay(); // 0=الأحد
  if (dow !== 6 && dow !== 0) return;
  const { date } = cairoParts();
  const groups = await db.collection('groups').where('status', '==', 'active').get();
  const byOwner = {};
  groups.forEach((g) => { const d = g.data(); const est = (Number(d.storageBytes || 0) / GB) * PRICE_PER_GB_WEEK + Number(d.memberCount || 0) * PRICE_PER_STUDENT_WEEK; byOwner[d.ownerUid] = (byOwner[d.ownerUid] || 0) + est; });
  for (const [ownerUid, est] of Object.entries(byOwner)) {
    if (est <= 0) continue;
    const balance = await walletBalance(ownerUid);
    if (balance < est) await notify(ownerUid, 'اشحن رصيدك قبل موعد الخصم', `رسوم مجموعاتك التقديرية هذا الأسبوع ${round2(est)} جنيه ورصيدك ${balance} جنيه. اشحن رصيدك وإلا ستُجمّد المجموعة بعد يومين من موعد الاستحقاق.`, { type: 'group_low_balance' }, `glow_${ownerUid}_${date}`);
  }
});

/** كل ساعة: تسوية تلقائية بعد الشحن، ثم تجميد بعد 48 ساعة، ثم حذف نهائي بعد 7 أيام من التجميد. */
exports.groupFreezeAndPurge = onSchedule({ schedule: 'every 1 hours', timeZone: TZ, secrets: R2_SECRETS, timeoutSeconds: 540 }, async () => {
  const due = await db.collection('groups').where('freezeAt', '<=', TS.now()).get();
  for (const g of due.docs) {
    try {
      const d = g.data();
      const r = await settleOwnerBills(d.ownerUid);
      await refreshGroupBillingState(g.id);
      const fresh = (await g.ref.get()).data();
      if (!fresh) continue;
      if (fresh.status === 'active' && fresh.freezeAt) {
        await g.ref.update({ status: 'frozen', frozenAt: FV.serverTimestamp(), purgeAt: TS.fromMillis(Date.now() + PURGE_AFTER_DAYS * 24 * 3600 * 1000) });
        await notify(d.ownerUid, 'تم تجميد مجموعتك', `تم تجميد «${d.name}» لعدم سداد الرسوم. ادفع خلال ${PURGE_AFTER_DAYS} أيام لاسترجاعها وإلا ستُحذف نهائيًا.`, { type: 'group_frozen', groupId: g.id }, `gfrozen_${g.id}`);
        const members = await g.ref.collection('members').get();
        for (const m of members.docs) await notify(m.id, 'المجموعة متوقفة مؤقتًا', `مجموعة «${d.name}» متوقفة مؤقتًا.`, { type: 'group_frozen', groupId: g.id }, `gfrozen_${g.id}`);
      } else if (fresh.status === 'frozen' && fresh.purgeAt?.toMillis?.() <= Date.now()) {
        await purgeGroup(g.id);
      }
    } catch (e) { console.error('freeze/purge', g.id, e); }
  }
});

/** المُفهم يدفع الرسوم المستحقة بنفسه من رصيده (تسوية فورية + إعادة تفعيل). */
exports.payGroupBills = onCall(async (request) => {
  const uid = reqUid(request);
  const r = await settleOwnerBills(uid);
  for (const gid of r.groups) await refreshGroupBillingState(gid);
  if (r.remaining > 0) throw new HttpsError('failed-precondition', 'رصيدك لا يكفي لسداد كل الفواتير، اشحن رصيدك أولًا');
  return { ok: true, paid: r.paid };
});
