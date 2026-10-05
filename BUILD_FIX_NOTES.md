V20 changes:
- Restored Firebase email verification flow with /verify-email screen.
- Login sends unverified users to verification instead of /home.
- Signup sends verification email and opens verification screen.
- Router redirects authenticated but unverified users to /verify-email.
- Verification screen supports reload/check, resend, and logout.
- Courses continue to load from Firestore `courses` where `status == published`.
- Added getPublishedCoursesOnce() helper for reliable one-shot course loading.
- Existing R2 token URL conversion remains in Course.fromMap for course thumbnails.
- No course deletion or replacement logic was introduced.
