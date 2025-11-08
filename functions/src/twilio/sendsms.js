/**
 * This file uses the modern ES Module (ESM) syntax with `import` and `export`.
 * It requires "type": "module" in your functions/package.json file.
 */

// ESM style: Use `import` instead of `require`.
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import twilio from "twilio";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

// --- Initialization ---
initializeApp();
const db = getFirestore();

// Define the secrets needed for the Twilio API
const twilioAccountSid = defineSecret("TWILIO_ACCOUNT_SID");
const twilioAuthToken = defineSecret("TWILIO_AUTH_TOKEN");


// --- Callable Function: sendSms ---
export const sendSms = onCall({ secrets: [twilioAccountSid, twilioAuthToken] }, async (request) => {
  const accountSid = twilioAccountSid.value();
  const authToken = twilioAuthToken.value();
  const client = twilio(accountSid, authToken);

  // Destructure the new argument, defaulting to 'sms'
  const { phoneNumber, docId, verificationType = 'sms' }
  = request.data;

  if (!phoneNumber || !docId) {
    logger.error("Request was missing phoneNumber or docId.", { structuredData: true });
    throw new HttpsError("invalid-argument", "Missing 'phoneNumber' or 'docId'.");
  }

  // Use the same Twilio number for all sends.
  const twilioSmsNumber = "+13204139419";
  const otp = Math.floor(100000 + Math.random() * 900000).toString();
  const expiry = new Date(Date.now() + 10 * 60 * 1000); // 10 minute expiry

  let messageBody;

  // Conditional logic for the message content ONLY.
  if (verificationType === 'whatsapp') {
    messageBody = `Your MyFellowPet verification code to verify your WhatsApp number as part of the Home Boarder registration process is: ${otp}. This code is valid for 10 minutes.`;
  } else { // Default to SMS
    messageBody = `Your MyFellowPet verification code to verify your phone number as part of the Home Boarder registration process is: ${otp}. This code is valid for 10 minutes.`;
  }


  try {
    // We save to the same field, as the verification function is generic.
    await db.collection("verification_codes").doc(docId).set({
      phoneOtp: otp,
      phoneOtpExpiry: expiry,
    }, { merge: true });

    logger.info(`OTP ${otp} saved for docId ${docId} via ${verificationType}. Sending message.`);

    // The `to` and `from` numbers are now treated the same way for both types.
    await client.messages.create({
      to: phoneNumber, // The E.164 number from the client
      from: twilioSmsNumber, // Your standard Twilio SMS number
      body: messageBody,
    });

    logger.info(`${verificationType.toUpperCase()} type message sent successfully to ${phoneNumber}.`);
    return { success: true, message: `Verification code sent to your ${verificationType === 'whatsapp' ? 'WhatsApp' : 'Phone'} number.` };

  } catch (error) {
    logger.error(`Failed to send ${verificationType.toUpperCase()} to ${phoneNumber}.`, { error: error.message });
    throw new HttpsError("internal", `Could not send verification code.`, error.message);
  }
});


// --- Callable Function: verifySmsCode (No changes needed) ---
export const verifySmsCode = onCall(async (request) => {
  const { code, docId } = request.data;

  if (!code || !docId) {
    logger.error("Request missing code or docId.", { structuredData: true });
    throw new HttpsError("invalid-argument", "Missing 'code' or 'docId'.");
  }

  const docRef = db.collection("verification_codes").doc(docId);
  const docSnap = await docRef.get();

  if (!docSnap.exists) {
    logger.warn(`Verification attempt for non-existent docId: ${docId}`);
    throw new HttpsError("not-found", "Invalid code or session expired. Please try again.");
  }

  const data = docSnap.data();
  const storedCode = data.phoneOtp;
  const expiry = data.phoneOtpExpiry.toDate();

  // Invalidate the code after one attempt
  await docRef.update({
    phoneOtp: null,
    phoneOtpExpiry: null,
  });

  if (storedCode !== code) {
    logger.warn(`Incorrect code provided for docId: ${docId}`);
    throw new HttpsError("invalid-argument", "The code you entered is incorrect.");
  }

  if (new Date() > expiry) {
    logger.warn(`Expired code used for docId: ${docId}`);
    throw new HttpsError("deadline-exceeded", "The verification code has expired. Please request a new one.");
  }

  logger.info(`Phone successfully verified for docId: ${docId}`);
  return { success: true, message: "Phone number verified successfully!" };
});
