/**
 * 🐾 MyFellowPet Secure Cloud Functions
 * Node 18 | Firebase v2 | Nodemailer | Secrets API
 */

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const nodemailer = require('nodemailer');
const { defineSecret } = require('firebase-functions/params');

// ==========================================================
// 🔑 SECRETS
// ==========================================================
// firebase functions:secrets:set SMTP_HOST
// firebase functions:secrets:set SMTP_PORT
// firebase functions:secrets:set SMTP_USER
// firebase functions:secrets:set SMTP_PASS
// firebase functions:secrets:set APP_NAME
// firebase functions:secrets:set BRAND_COLOR

const smtpHost = defineSecret('SMTP_HOST');
const smtpPort = defineSecret('SMTP_PORT');
const smtpUser = defineSecret('SMTP_USER');
const smtpPass = defineSecret('SMTP_PASS');
const brandColor = defineSecret('BRAND_COLOR');
const appName = defineSecret('APP_NAME');

// ==========================================================
// 🏁 Initialize Firebase Admin (singleton)
// ==========================================================
if (getApps().length === 0) initializeApp();
const db = getFirestore();
const auth = getAuth();

// ==========================================================
// 💌 Helper — Email Template Wrapper
// ==========================================================
function emailWrapper(title, bodyHtml, color, appName) {
  return `
    <div style="font-family:Poppins,Arial,sans-serif; background:#f5f6fa; padding:40px 0;">
      <div style="max-width:520px; margin:auto; background:#fff; border-radius:12px;
                  box-shadow:0 4px 14px rgba(0,0,0,0.08); overflow:hidden;">
        <div style="background:${color}; color:#fff; text-align:center; padding:16px 0;">
          <h2 style="margin:0; font-size:22px;">${appName}</h2>
        </div>
        <div style="padding:32px; color:#333;">
          ${bodyHtml}
        </div>
        <hr style="border:none; border-top:1px solid #eee;">
        <p style="font-size:12px; color:#999; text-align:center; padding:8px 16px;">
          This is an automated email from ${appName}. Please do not reply.
        </p>
      </div>
    </div>
  `;
}

// ==========================================================
// 1️⃣ sendEmailOtp — triggered when user taps “Forgot PIN?”
// ==========================================================
exports.sendEmailOtp = onCall(
  { secrets: [smtpHost, smtpPort, smtpUser, smtpPass, brandColor, appName], region: 'asia-south1' },
  async (req) => {
    const { uid, email } = req.data;
    if (!email || !uid) {
      throw new HttpsError('invalid-argument', 'Missing UID or email.');
    }

    const code = Math.floor(100000 + Math.random() * 900000).toString();

    await db.collection('email_verifications').doc(uid).set({
      code,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: Date.now() + 15 * 60 * 1000, // 15 minutes
    });

    const transporter = nodemailer.createTransport({
      host: smtpHost.value(),
      port: parseInt(smtpPort.value(), 10),
      secure: true,
      auth: { user: smtpUser.value(), pass: smtpPass.value() },
    });

    const htmlBody = `
      <p>Hi there,</p>
      <p>We received a request to verify your ${appName.value()} account.</p>
      <p style="text-align:center; margin:20px 0;">
        <span style="display:inline-block; background:${brandColor.value()};
                     color:#fff; padding:10px 18px; border-radius:8px;
                     font-size:22px; font-weight:bold; letter-spacing:2px;">
          ${code}
        </span>
      </p>
      <p>This code will expire in 15 minutes. If you didn’t request this, ignore this email.</p>
    `;

    await transporter.sendMail({
      from: `"${appName.value()}" <${smtpUser.value()}>`,
      to: email,
      subject: `${appName.value()} - Your 6-digit Verification Code`,
      html: emailWrapper('Verify Your Account', htmlBody, brandColor.value(), appName.value()),
    });

    return { success: true };
  }
);

// ==========================================================
// 2️⃣ notifyLockedAccount — Firestore trigger (status locked)
// ==========================================================
exports.notifyLockedAccount = onDocumentUpdated(
  { document: 'users/{uid}', secrets: [smtpHost, smtpPort, smtpUser, smtpPass, brandColor, appName] },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    if (before.account_status !== 'locked' && after.account_status === 'locked') {
      const email = after.email;
      if (!email) return;

      const transporter = nodemailer.createTransport({
        host: smtpHost.value(),
        port: parseInt(smtpPort.value(), 10),
        secure: true,
        auth: { user: smtpUser.value(), pass: smtpPass.value() },
      });

      await db.doc(`users/${event.params.uid}`).update({
        locked_at: FieldValue.serverTimestamp(),
      });

      const htmlBody = `
        <p>Hello,</p>
        <p>Your ${appName.value()} account has been temporarily locked for security reasons.</p>
        <p>We noticed a login attempt after more than 60 days of inactivity. To protect your data,
           we’ve paused access for <b>72 hours</b>.</p>
        <p>If this was you, simply log in again within 72 hours using your verified PIN to restore access.</p>
        <p>If no action is taken, we’ll safely remove the old account so the number can be reused.</p>
        <p style="margin-top:20px;">Stay safe,<br>The ${appName.value()} Team 🐾</p>
      `;

      await transporter.sendMail({
        from: `"${appName.value()}" <${smtpUser.value()}>`,
        to: email,
        subject: `${appName.value()} Account Locked for Security`,
        html: emailWrapper('Account Locked', htmlBody, brandColor.value(), appName.value()),
      });
    }
  }
);

// ==========================================================
// 3️⃣ cleanupLockedAccounts — runs hourly to delete expired locks
// ==========================================================
exports.cleanupLockedAccounts = onSchedule(
  { schedule: 'every 1 hours', secrets: [smtpHost, smtpPort, smtpUser, smtpPass, brandColor, appName] },
  async () => {
    const cutoff = Date.now() - 72 * 60 * 60 * 1000; // 72 hours (3 days)
    const snap = await db.collection('users').where('account_status', '==', 'locked').get();

    const transporter = nodemailer.createTransport({
      host: smtpHost.value(),
      port: parseInt(smtpPort.value(), 10),
      secure: true,
      auth: { user: smtpUser.value(), pass: smtpPass.value() },
    });

    let deletedCount = 0;

    for (const doc of snap.docs) {
      const data = doc.data();
      const lockedAt = data.locked_at?.toDate?.();
      if (!lockedAt || lockedAt.getTime() > cutoff) continue;

      if (data.email) {
        const htmlBody = `
          <p>Hello,</p>
          <p>As part of our security policy, your ${appName.value()} account has been safely removed
             because it remained locked for over 72 hours.</p>
          <p>If you are the rightful owner, you can always re-register anytime using your number.</p>
          <p>Thank you,<br>The ${appName.value()} Team 🐾</p>
        `;

        await transporter.sendMail({
          from: `"${appName.value()}" <${smtpUser.value()}>`,
          to: data.email,
          subject: `${appName.value()} Account Removed`,
          html: emailWrapper('Account Removed', htmlBody, brandColor.value(), appName.value()),
        });
      }

      await auth.deleteUser(doc.id).catch(() => {});
      await doc.ref.delete().catch(() => {});
      deletedCount++;
    }

    console.log(`✅ Cleanup complete: ${deletedCount} accounts deleted.`);
  }
);
