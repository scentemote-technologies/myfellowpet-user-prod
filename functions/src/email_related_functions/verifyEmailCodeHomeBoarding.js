import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import nodemailer from 'nodemailer';
import { defineSecret } from 'firebase-functions/params';

// 🔑 SECRETS
const smtpHost = defineSecret('SMTP_HOST');
const smtpPort = defineSecret('SMTP_PORT');
const smtpUser = defineSecret('SMTP_USER');
const smtpPass = defineSecret('SMTP_PASS');

// ==========================================================
// ✅ CORRECT INITIALIZATION LOGIC (Runs ONCE per container)
// ==========================================================
// This check prevents the "app/duplicate-app" error on warm restarts.
if (getApps().length === 0) {
    initializeApp();
}

// 🌐 Get the Firestore reference once globally
const db = getFirestore();
// ==========================================================


export const sendEmailVerificationCode = onCall(
  { secrets: [smtpHost, smtpPort, smtpUser, smtpPass], region: 'asia-south1' },
  async (req) => {
    // Initialization is now handled globally, so it's removed from here.

    const { email, docId } = req.data;
    if (!email || !docId) {
      throw new HttpsError('invalid-argument', 'Missing required parameters: email or docId.');
    }

    const code = Math.floor(100000 + Math.random() * 900000).toString();

    const verificationRef = db
      .collection('users-sp-boarding')
      .doc(docId)
      .collection('verifications')
      .doc('notification_email');

    // Store the code and its creation timestamp
    await verificationRef.set({
      code: code,
      email: email,
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

    // ==========================================================
    // ✨ IMPROVED EMAIL BODY (Professional and clear design)
    // ==========================================================
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
        to: email,
        subject: 'Your MyFellowPet Email Verification Code',
        html: htmlBody,
    };
    // ==========================================================

    try {
      await transporter.sendMail(mailOptions);
      return { success: true, message: `Verification code sent to ${email}.` };
    } catch (error) {
      console.error('Failed to send email:', error);
      throw new HttpsError('internal', 'Could not send verification email.');
    }
  }
);

export const verifyEmailCode = onCall(
  { region: 'asia-south1' },
  async (req) => {
    // Initialization is now handled globally, so it's removed from here.

    const { code, docId } = req.data;
    if (!code || !docId) {
      throw new HttpsError('invalid-argument', 'Missing required parameters: code or docId.');
    }

    const verificationRef = db
      .collection('users-sp-boarding')
      .doc(docId)
      .collection('verifications')
      .doc('notification_email');
    const verificationDoc = await verificationRef.get();

    if (!verificationDoc.exists) {
      throw new HttpsError('not-found', 'No verification request found. Please send a new code.');
    }

    const { code: savedCode, createdAt } = verificationDoc.data();

    // Check for expiration (10 minutes)
    const tenMinutesInMillis = 10 * 60 * 1000;
    if (Date.now() - createdAt.toMillis() > tenMinutesInMillis) {
      await verificationRef.delete();
      throw new HttpsError('deadline-exceeded', 'The verification code has expired.');
    }

    if (savedCode !== code) {
      throw new HttpsError('invalid-argument', 'The code you entered is incorrect.');
    }

    // Mark the email as verified on the main document
    const mainDocRef = db.collection('users-sp-boarding').doc(docId);
    await mainDocRef.set({
         notification_email_verified: true,
       }, { merge: true });

    await verificationRef.delete();

    return { success: true, message: 'Email successfully verified!' };
  }
);