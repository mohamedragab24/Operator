# Admin course review dashboard

The Flutter app now exposes `/admin` only to users whose Firestore profile has `role: "admin"` (or a Firebase Auth custom claim `admin: true`).

The Account tab shows **لوحة الأدمن — مراجعة الكورسات** only for that role.

The callable Cloud Function `reviewCourse` is the trusted write path. It changes a pending course to `published` on approval or `rejected` on rejection, requires a rejection reason, appends an audit record under `courses/{courseId}/reviews`, and sends a notification to the course owner when `ownerUid`, `instructorUid`, or `createdBy` exists.

For production, grant admin access using a trusted server/Admin SDK by setting the user's `role` field to `admin` and/or the Firebase Auth custom claim `admin: true`. Do not let normal users write their own role.
