/**
 * 🐾 MyFellowPet Secure Cloud Functions
 * Node 18 | Firebase v2 | Nodemailer | Secrets API
 */

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { defineSecret } = require('firebase-functions/params');
const nodemailer = require('nodemailer');

// Initialize Firebase Admin
if (getApps().length === 0) initializeApp();
const db = getFirestore();

// Secrets
const smtpHost = defineSecret('SMTP_HOST');
const smtpPort = defineSecret('SMTP_PORT');
const smtpUser = defineSecret('SMTP_USER');
const smtpPass = defineSecret('SMTP_PASS');
const brandColor = defineSecret('BRAND_COLOR');
const appName = defineSecret('APP_NAME');

// Helper: Email Wrapper
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
          This is an automated email from ${appName}.
        </p>
      </div>
    </div>
  `;
}

// ==========================================================
// 1️⃣ SEND Signup OTP (New Collection: signup_verifications)
// ==========================================================
exports.sendSignupOtp = onCall(
  { secrets: [smtpHost, smtpPort, smtpUser, smtpPass, brandColor, appName], region: 'asia-south1' },
  async (req) => {
    // We don't need UID necessarily if the user isn't created yet,
    // but usually we use the Auth UID if they just signed up via Auth but haven't made a profile.
    // If you don't have a UID yet, pass the email as the key.
    // Here assuming you are logged in (Anonymous or Auth) and have a UID.
    const { uid, email } = req.data;

    if (!email || !uid) {
      throw new HttpsError('invalid-argument', 'Missing UID or email.');
    }

    const code = Math.floor(100000 + Math.random() * 900000).toString();

    // 🔴 DIFFERENT COLLECTION NAME
    await db.collection('signup_verifications').doc(uid).set({
      email: email, // Store email to ensure they verify the same one they asked for
      code: code,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: Date.now() + 15 * 60 * 1000, // 15 mins
    });

    const transporter = nodemailer.createTransport({
      host: smtpHost.value(),
      port: parseInt(smtpPort.value(), 10),
      secure: true,
      auth: { user: smtpUser.value(), pass: smtpPass.value() },
    });

    const htmlBody = `
      <p>Welcome!</p>
      <p>To complete your account setup, please verify your email address.</p>
      <p style="text-align:center; margin:20px 0;">
        <span style="display:inline-block; background:${brandColor.value()};
                     color:#fff; padding:10px 18px; border-radius:8px;
                     font-size:22px; font-weight:bold; letter-spacing:2px;">
          ${code}
        </span>
      </p>
    `;

    await transporter.sendMail({
      from: `"${appName.value()}" <${smtpUser.value()}>`,
      to: email,
      subject: `${appName.value()} - Verify your Email`,
      html: emailWrapper('Verify Email', htmlBody, brandColor.value(), appName.value()),
    });

    return { success: true };
  }
);

// ==========================================================
// 2️⃣ VERIFY Signup OTP
// ==========================================================
exports.verifySignupOtp = onCall(
  { region: 'asia-south1' }, // No secrets needed here
  async (req) => {
    const { uid, code, email } = req.data;

    if (!uid || !code || !email) {
      throw new HttpsError('invalid-argument', 'Missing details.');
    }

    const docRef = db.collection('signup_verifications').doc(uid);
    const docSnap = await docRef.get();

    if (!docSnap.exists) {
      throw new HttpsError('not-found', 'No verification code found.');
    }

    const data = docSnap.data();

    // 1. Check Expiration
    if (Date.now() > data.expiresAt) {
      throw new HttpsError('deadline-exceeded', 'Code has expired.');
    }

    // 2. Check Code Match
    if (data.code !== code) {
      throw new HttpsError('permission-denied', 'Invalid code.');
    }

    // 3. Check Email Match (prevent swapping email after sending code)
    if (data.email !== email) {
       throw new HttpsError('permission-denied', 'Email does not match request.');
    }

    // Success! Delete the doc so it can't be reused (optional, but good security)
    await docRef.delete();

    return { success: true };
  }
);