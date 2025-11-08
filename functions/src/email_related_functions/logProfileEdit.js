const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const {FieldValue} = require("firebase-admin/firestore");

admin.initializeApp();

// Define secrets.
const smtpHost = defineSecret("SMTP_HOST");
const smtpPort = defineSecret("SMTP_PORT");
const smtpUser = defineSecret("SMTP_USER");
const smtpPass = defineSecret("SMTP_PASS");

/**
 * Generates a random 6-digit numeric string for OTP.
 * @return {string} The 6-digit OTP.
 */
function generateOtp() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

// v2 Callable Function to handle sending OTPs for email/phone changes.
exports.sendChangeOtp = onCall(
    {secrets: [smtpHost, smtpPort, smtpUser, smtpPass]},
    async (request) => {
      const {uid, newEmail, oldEmail} = request.data;
      const authUser = request.auth;

      // 1. Security Check: User must be authenticated to edit their own profile.
      if (!authUser || authUser.uid !== uid) {
        throw new HttpsError(
            "unauthenticated",
            "You must be logged in to do this.",
        );
      }

      // 2. Data Validation.
      if (!newEmail || !oldEmail) {
        throw new HttpsError(
            "invalid-argument",
            "Missing new or old email address.",
        );
      }

      // 3. Check for Existing User: Verify new email is not already in use.
      try {
        const userRecord = await admin.auth().getUserByEmail(newEmail);
        if (userRecord) {
          throw new HttpsError(
              "already-exists",
              "This email is already linked to another account.",
          );
        }
      } catch (error) {
        if (error.code !== "auth/user-not-found") {
          console.error("Error checking for existing user:", error);
          throw new HttpsError(
              "internal",
              "An error occurred while checking the new email.",
          );
        }
        // "auth/user-not-found" is the success case, meaning we can proceed.
      }

      // 4. Generate and Store OTPs
      const otpForNewEmail = generateOtp();
      const otpForOldEmail = generateOtp();
      const otpExpiry = new Date(Date.now() + 10 * 60 * 1000); // 10 mins

      try {
        const userDocRef = admin.firestore().collection("users").doc(uid);
        await userDocRef.set({
          pending_email_change: {
            new_email: newEmail,
            old_email: oldEmail,
            otp_new: otpForNewEmail,
            otp_old: otpForOldEmail,
            expires_at: otpExpiry,
          },
        }, {merge: true});
      } catch (error) {
        console.error("Firestore update failed:", error);
        throw new HttpsError(
            "internal",
            "Could not save OTPs. Please try again.",
        );
      }

      // 5. Send Emails with OTPs
      const transporter = nodemailer.createTransport({
        host: smtpHost.value(),
        port: parseInt(smtpPort.value(), 10),
        secure: true, // true for 465, false for other ports
        auth: {
          user: smtpUser.value(),
          pass: smtpPass.value(),
        },
      });

      const mailOptionsNew = {
        from: `"Your App Name" <${smtpUser.value()}>`,
        to: newEmail,
        subject: "Confirm Your New Email Address",
        text: `Your verification code is: ${otpForNewEmail}. ` +
              "It will expire in 10 minutes.",
        html: `<b>Your verification code is: ${otpForNewEmail}</b>. ` +
              "It will expire in 10 minutes.",
      };

      const mailOptionsOld = {
        from: `"Your App Name" <${smtpUser.value()}>`,
        to: oldEmail,
        subject: "Security Alert: Email Change Requested",
        text: "A request was made to change the email on your account. " +
              `Your verification code is: ${otpForOldEmail}. ` +
              "It will expire in 10 minutes. If you did not request this, " +
              "please secure your account.",
        html: "A request was made to change the email on your account. " +
              `Your verification code is: <b>${otpForOldEmail}</b>. ` +
              "It will expire in 10 minutes. If you did not request this, " +
              "please secure your account.",
      };

      try {
        await transporter.sendMail(mailOptionsNew);
        await transporter.sendMail(mailOptionsOld);
        return {success: true, message: "OTPs sent."};
      } catch (error) {
        console.error("Failed to send OTP emails:", error);
        throw new HttpsError(
            "internal",
            "Could not send OTP emails. Please try again.",
        );
      }
    },
);


/**
 * Firestore trigger to automatically log all changes to a user's profile
 * in a subcollection for auditing purposes.
 */
exports.logProfileEdit = onDocumentUpdated("users/{userId}", (event) => {
  if (!event.data) {
    console.log("No data associated with the event, skipping log.");
    return;
  }

  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();

  // Find fields that were actually changed
  const changedFields = Object.keys(afterData).filter((field) => {
    // We don't want to log the OTP data itself for security
    if (field === "pending_email_change") return false;
    return beforeData[field] !== afterData[field];
  });

  if (changedFields.length === 0) {
    console.log("No relevant fields changed, skipping log.");
    return null;
  }

  const edits = changedFields.map((field) => {
    const fromValue = (beforeData[field] !== undefined &&
                       beforeData[field] !== null) ? beforeData[field] : null;

    return {
      field: field,
      from: fromValue,
      to: afterData[field],
      changedAt: FieldValue.serverTimestamp(),
      actor: {
        uid: event.params.userId,
      },
    };
  });

  if (edits.length > 0) {
    const logRef = event.data.after.ref.collection("user_profile_edits");
    const batch = admin.firestore().batch();
    edits.forEach((edit) => {
      const newLogRef = logRef.doc();
      batch.set(newLogRef, edit);
    });
    return batch.commit();
  }

  return null;
});

