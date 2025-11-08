import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import nodemailer from 'nodemailer';
import { defineSecret } from 'firebase-functions/params';

// 🔑 SECRETS (Must be defined via CLI: firebase functions:secrets:set)
const smtpHost = defineSecret('SMTP_HOST');
const smtpPort = defineSecret('SMTP_PORT');
const smtpUser = defineSecret('SMTP_USER');
const smtpPass = defineSecret('SMTP_PASS');

// Global Initialization
if (getApps().length === 0) {
    initializeApp();
}
const db = getFirestore();

// ==========================================================
// PET STORE: SEND CODE (sendPetStoreEmailVerificationCode)
// ==========================================================
export const sendPetStoreEmailVerificationCode = onCall(
  {
    secrets: [smtpHost, smtpPort, smtpUser, smtpPass],
    region: 'asia-south1',
    cors: true // CORS ENABLED for V2
  },
  async (req) => {
    const { email, docId } = req.data;

    const cleanEmail = email ? email.trim() : null;

    if (!cleanEmail || !docId) {
      throw new new HttpsError('invalid-argument', 'Missing required parameters: email or docId.');
    }

    const code = Math.floor(100000 + Math.random() * 900000).toString();

    // 🛑 COLLECTION: users-sp-store
    const verificationRef = db
      .collection('users-sp-store')
      .doc(docId)
      .collection('verifications')
      .doc('notification_email');

    await verificationRef.set({
      code: code,
      email: cleanEmail,
      createdAt: FieldValue.serverTimestamp(),
    });

    const transporter = nodemailer.createTransport({
      host: smtpHost.value(),
      port: parseInt(smtpPort.value(), 10),
      secure: true,
      auth: {
        user: smtpUser.value(),
        pass: smtpPass.value(),
      },
    });

    const htmlBody = `
      <div style="font-family: Arial, sans-serif; line-height: 1.6; color: #333333; max-width: 600px; margin: 0 auto; border: 1px solid #e0e0e0; border-radius: 8px; overflow: hidden;">
          <div style="background-color: #2D3748; color: #ffffff; padding: 20px; text-align: center;">
              <h1 style="margin: 0; font-size: 24px; font-weight: 600;">MyFellowPet Verification</h1>
          </div>
          <div style="padding: 30px;">
              <p style="font-size: 16px;">Hello,</p>
              <p style="font-size: 16px;">
                  Thank you for starting your partnership application with **MyFellowPet**.
                  Please use the **One-Time Password (OTP)** below to verify your notification email address.
              </p>
              <div style="text-align: center; margin: 30px 0; border: 2px dashed #4C51BF; border-radius: 8px; background-color: #F7FAFC; padding: 20px;">
                  <p style="font-size: 14px; color: #718096; margin-bottom: 5px;">Your Verification Code:</p>
                  <h2 style="font-size: 32px; letter-spacing: 5px; color: #4C51BF; margin: 5px 0; font-weight: bold;">
                      ${code}
                  </h2>
              </div>
              <p style="font-size: 14px; color: #E53E3E;">
                  ⚠️ **This code is valid for 10 minutes only.** Do not share this code with anyone.
              </p>
              <p style="font-size: 16px;">If you did not request this code, please ignore this email.</p>
              <p style="font-size: 16px; margin-top: 30px;">
                  Best regards,<br>The MyFellowPet Team
              </p>
          </div>
          <div style="background-color: #f4f4f4; color: #718096; padding: 15px; text-align: center; font-size: 12px; border-top: 1px solid #e0e0e0;">
              &copy; 2025 MyFellowPet. All rights reserved.
          </div>
      </div>
    `;

    const mailOptions = {
        from: `"MyFellowPet" <${smtpUser.value()}>`,
        to: cleanEmail,
        subject: 'Your MyFellowPet Email Verification Code',
        html: htmlBody,
    };

    try {
      await transporter.sendMail(mailOptions);
      return { success: true, message: `Verification code sent to ${cleanEmail}.` };
    } catch (error) {
      console.error('Failed to send email:', error);
      throw new HttpsError('internal', 'Could not send verification email.');
    }
  }
);

// ==========================================================
// PET STORE: VERIFY CODE (verifyPetStoreEmailCode)
// ==========================================================
export const verifyPetStoreEmailCode = onCall(
  { region: 'asia-south1', cors: true }, // CORS ENABLED
  async (req) => {

    const { code: rawCode, docId } = req.data;

    // 💡 Trim the code and check for missing params
    const code = rawCode ? rawCode.trim() : null;

    if (!code || !docId) {
      throw new HttpsError('invalid-argument', 'Missing required parameters: code or docId.');
    }

    // 🛑 COLLECTION: users-sp-store
    const verificationRef = db
      .collection('users-sp-store')
      .doc(docId)
      .collection('verifications')
      .doc('notification_email');
    const verificationDoc = await verificationRef.get();

    if (!verificationDoc.exists) {
      throw new HttpsError('not-found', 'No verification request found. Please send a new code.');
    }

    const data = verificationDoc.data();

    // 🛑 DEFENSIVE CHECK: Prevents the .toMillis() crash (the previous "internal" error)
    if (!data || !data.createdAt || typeof data.createdAt.toMillis !== 'function' || !data.code) {
        console.error('CRASH PREVENTED: Verification data is corrupt or missing Timestamp.', data);
        throw new HttpsError('internal', 'Verification data is corrupt or incomplete.');
    }

    const { code: savedCode, createdAt } = data; // Safe destructuring

    // Check for expiration (10 minutes)
    const tenMinutesInMillis = 10 * 60 * 1000;

    if (Date.now() - createdAt.toMillis() > tenMinutesInMillis) {
      await verificationRef.delete();
      throw new HttpsError('deadline-exceeded', 'The verification code has expired.');
    }

    // Check against the clean code
    if (savedCode !== code) {
      throw new HttpsError('invalid-argument', 'The code you entered is incorrect.');
    }

    // 🛑 COLLECTION: users-sp-store
    const mainDocRef = db.collection('users-sp-store').doc(docId);
    await mainDocRef.set({
          notification_email_verified: true,
        }, { merge: true });

    await verificationRef.delete();

    return { success: true, message: 'Email successfully verified!' };
  }
);


