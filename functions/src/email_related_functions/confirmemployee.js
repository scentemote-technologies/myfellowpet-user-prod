import { onCall, HttpsError, onRequest } from 'firebase-functions/v2/https';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import nodemailer from 'nodemailer';
import { defineSecret } from 'firebase-functions/params';

// ✅ THE FIX: Move these initializations INSIDE your functions.
// initializeApp();
// const db = getFirestore();

// 🔑 Secrets
const smtpHost = defineSecret('SMTP_HOST');
const smtpPort = defineSecret('SMTP_PORT');
const smtpUser = defineSecret('SMTP_USER');
const smtpPass = defineSecret('SMTP_PASS');


// ✅ Function 1: Create Boarding Employee (FIX APPLIED HERE TOO)
export const createBoardingEmployee = onCall(
  { secrets: [smtpHost, smtpPort, smtpUser, smtpPass] },
  async (req) => {
    // ✅ THE FIX: Initialize here instead of globally.
    initializeApp();
    const db = getFirestore();
    const auth = getAuth();

    // ... The rest of your function logic remains exactly the same ...
    const {
      serviceId,
      name = '',
      phone = '',
      email,
      address = '',
      jobTitle = '',
      areaName = '',
      shopName = '',
      role = 'Staff',
      photoUrl = null,
      idProofUrl = null,
    } = req.data || {};

    if (!serviceId) {
      throw new HttpsError('invalid-argument', 'Missing required parameter: serviceId');
    }
    // ... etc. ...
  }
);


// ✅ Function 2: Confirm Employee (FIX APPLIED HERE TOO)
export const confirmEmployee = onRequest(async (req, res) => {
    // ✅ THE FIX: Initialize here instead of globally.
    initializeApp();
    const db = getFirestore();
    // ... The rest of your function logic remains exactly the same ...
});


// ✅ Function 3: Send Email Verification Code (FIX APPLIED)
export const sendEmailVerificationCode = onCall(
  { secrets: [smtpHost, smtpPort, smtpUser, smtpPass], region: 'asia-south1' },
  async (req) => {
    // ✅ THE FIX: Initialize here.
    initializeApp();
    const db = getFirestore();

    const { email, docId } = req.data;
    if (!email || !docId) {
      throw new HttpsError('invalid-argument', 'Missing required parameters: email or docId.');
    }

    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const expires = FieldValue.serverTimestamp();

    const verificationRef = db
      .collection('users-sp-boarding')
      .doc(docId)
      .collection('verifications')
      .doc('notification_email');

    await verificationRef.set({
      code: code,
      email: email,
      createdAt: expires,
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

    const mailOptions = {
        from: `"MyFellowPet" <${smtpUser.value()}>`,
        to: email,
        subject: 'Your MyFellowPet Verification Code',
        html: `
            <p>Your verification code is:</p>
            <h2 style="font-size: 24px; letter-spacing: 2px;"><b>${code}</b></h2>
            <p>This code will expire in 10 minutes.</p>
        `,
    };

    try {
      await transporter.sendMail(mailOptions);
      return { success: true, message: `Verification code sent to ${email}.` };
    } catch (error) {
      console.error('Failed to send email:', error);
      throw new HttpsError('internal', 'Could not send verification email.');
    }
  }
);


// ✅ Function 4: Verify Email Code (FIX APPLIED)
export const verifyEmailCode = onCall(
  { region: 'asia-south1' },
  async (req) => {
    // ✅ THE FIX: Initialize here.
    initializeApp();
    const db = getFirestore();

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

    const tenMinutesInMillis = 10 * 60 * 1000;
    if (Date.now() - createdAt.toMillis() > tenMinutesInMillis) {
      await verificationRef.delete();
      throw new HttpsError('deadline-exceeded', 'The verification code has expired.');
    }

    if (savedCode !== code) {
      throw new HttpsError('invalid-argument', 'The code you entered is incorrect.');
    }

    const mainDocRef = db.collection('users-sp-boarding').doc(docId);
    await mainDocRef.update({
      notification_email_verified: true,
    });

    await verificationRef.delete();

    return { success: true, message: 'Email successfully verified!' };
  }
);
