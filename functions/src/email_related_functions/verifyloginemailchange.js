// functions/index.js or functions/manageUsers.js

// Make sure you have these imports at the top of your file
import { onCall, HttpsError, onRequest } from 'firebase-functions/v2/https';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import nodemailer from 'nodemailer';
import { defineSecret } from 'firebase-functions/params';

// This should be called once at the top of your index.js
// initializeApp();

// Define secrets for sending emails
const smtpHost = defineSecret('SMTP_HOST');
const smtpPort = defineSecret('SMTP_PORT');
const smtpUser = defineSecret('SMTP_USER');
const smtpPass = defineSecret('SMTP_PASS');

/**
 * --- STEP 1 ---
 * Kicks off the login email change process by sending verification links
 * to both the old and new email addresses.
 */
export const requestLoginEmailChange = onCall(
  { secrets: [smtpHost, smtpPort, smtpUser, smtpPass] },
  async (req) => {
    const db = getFirestore();
    const auth = getAuth();

    const { newEmail } = req.data;
    const uid = req.auth?.uid;

    if (!uid) throw new HttpsError('unauthenticated', 'You must be logged in.');
    if (!newEmail || !newEmail.includes('@')) throw new HttpsError('invalid-argument', 'A valid new email is required.');

    const userRecord = await auth.getUser(uid);
    const oldEmail = userRecord.email;

    if (!oldEmail) throw new HttpsError('internal', 'Current user has no email address.');
    if (oldEmail === newEmail) throw new HttpsError('invalid-argument', 'New email cannot be the same as the old email.');

    // Create a temporary document to track the verification status
    const changeRequestRef = db.collection('loginEmailChanges').doc(uid);
    await changeRequestRef.set({
      uid,
      oldEmail,
      newEmail,
      oldVerified: false,
      newVerified: false,
      createdAt: FieldValue.serverTimestamp(),
    });

    // Function to send verification emails
    const sendVerificationEmail = async (email, type) => {
      const verifyUrl = `YOUR_CLOUD_FUNCTIONS_URL/verifyLoginEmailChange?uid=${uid}&email=${email}&type=${type}`;
      const transporter = nodemailer.createTransport({
        host: smtpHost.value(),
        port: parseInt(smtpPort.value(), 10),
        secure: true,
        auth: { user: smtpUser.value(), pass: smtpPass.value() },
      });
      await transporter.sendMail({
        from: `"Your App Name" <${smtpUser.value()}>`,
        to: email,
        subject: 'Confirm Your Login Email Change',
        html: `
          <h2>Please verify this email address</h2>
          <p>To continue changing your login email, please click the link below:</p>
          <a href="${verifyUrl}" style="padding:10px 15px;background:#4CAF50;color:#fff;text-decoration:none;">Verify Email Address</a>
          <p>If you did not request this change, you can safely ignore this email.</p>
        `,
      });
    };

    // Send emails to both old and new addresses
    await Promise.all([
      sendVerificationEmail(oldEmail, 'old'),
      sendVerificationEmail(newEmail, 'new'),
    ]);

    return { status: 'pending', message: 'Verification links sent to both email addresses.' };
  }
);


/**
 * --- STEP 2 ---
 * An HTTP function that is triggered when a user clicks a verification link.
 * It updates the status in the temporary tracking document.
 */
export const verifyLoginEmailChange = onRequest(async (req, res) => {
  const db = getFirestore();
  const { uid, email, type } = req.query;

  if (!uid || !email || !type) {
    return res.status(400).send('Missing required parameters.');
  }

  const changeRequestRef = db.collection('loginEmailChanges').doc(String(uid));
  const doc = await changeRequestRef.get();

  if (!doc.exists) {
    return res.status(404).send('Change request not found or already completed.');
  }

  const data = doc.data();
  if (type === 'old' && data.oldEmail === email) {
    await changeRequestRef.update({ oldVerified: true });
  } else if (type === 'new' && data.newEmail === email) {
    await changeRequestRef.update({ newVerified: true });
  } else {
    return res.status(400).send('Invalid verification link.');
  }

  return res.send('✅ Email verified successfully! You can now return to the app to complete the change.');
});


/**
 * --- STEP 3 ---
 * A final callable function that the app calls once the UI sees both emails
 * have been verified. This performs the actual, final update.
 */
export const finalizeLoginEmailChange = onCall(async (req) => {
  const db = getFirestore();
  const auth = getAuth();
  const uid = req.auth?.uid;

  if (!uid) throw new HttpsError('unauthenticated', 'You must be logged in.');

  const changeRequestRef = db.collection('loginEmailChanges').doc(uid);
  const doc = await changeRequestRef.get();

  if (!doc.exists) throw new HttpsError('not-found', 'Change request not found.');

  const { oldVerified, newVerified, newEmail } = doc.data();

  if (!oldVerified || !newVerified) {
    throw new HttpsError('failed-precondition', 'Both emails must be verified before finalizing.');
  }

  try {
    // 1. Update the email in Firebase Auth
    await auth.updateUser(uid, { email: newEmail });

    // 2. Update the login_email in all of the user's service documents
    const servicesRef = db.collection('users-sp-boarding');
    const querySnap = await servicesRef.where('shop_user_id', '==', uid).get();

    if (!querySnap.empty) {
      const batch = db.batch();
      querySnap.docs.forEach(doc => {
          batch.update(doc.ref, { login_email: newEmail });
      });
      await batch.commit();
    }

    // 3. Clean up by deleting the temporary request document
    await changeRequestRef.delete();

    return { status: 'success', message: 'Login email has been updated successfully.' };

  } catch (error) {
    console.error('Error finalizing email change:', error);
    if (error.code === 'auth/email-already-exists') {
      throw new HttpsError('already-exists', 'This email address is already in use by another account.');
    }
    throw new HttpsError('internal', 'An unexpected error occurred during the final update.');
  }
});
