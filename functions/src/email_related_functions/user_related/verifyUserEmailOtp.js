/**
 * 🐾 MyFellowPet Secure Cloud Functions
 * Node 18 | Firebase v2 | Nodemailer | Secrets API
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

// ✅ Initialize Firebase Admin once
if (getApps().length === 0) initializeApp();
const db = getFirestore();

// ==========================================================
// ✅ verifyUserEmailOtp — checks OTP in email_verifications/{uid}
// ==========================================================
export const verifyUserEmailOtp = onCall(
  { region: "asia-south1" },
  async (req) => {
    try {
      const { uid, code } = req.data;
      console.log("🔹 [verifyUserEmailOtp] Request received:", { uid, code });

      if (!uid || !code) {
        console.error("⚠️ Missing UID or code in request.");
        throw new HttpsError("invalid-argument", "Missing UID or code.");
      }

      const verificationRef = db.collection("email_verifications").doc(uid);
      const docSnap = await verificationRef.get();

      if (!docSnap.exists) {
        console.warn(`❌ No verification doc found for UID: ${uid}`);
        throw new HttpsError("not-found", "No verification found. Please request a new code.");
      }

      const data = docSnap.data();
      const { code: savedCode, expiresAt } = data;

      console.log("📄 [verifyUserEmailOtp] Fetched verification data:", data);

      // 🕒 Check expiry (expiresAt may be timestamp or millis)
      const now = Date.now();
      const expiryTime =
        typeof expiresAt === "object" && expiresAt.toDate
          ? expiresAt.toDate().getTime()
          : expiresAt;

      if (expiryTime && now > expiryTime) {
        console.warn(`⌛ Code expired for UID: ${uid}`);
        await verificationRef.delete();
        throw new HttpsError("deadline-exceeded", "Code expired. Please request a new one.");
      }

      if (savedCode !== code) {
        console.warn(`🚫 Incorrect code for UID: ${uid}`);
        throw new HttpsError("invalid-argument", "Incorrect code. Try again.");
      }

      // ✅ Mark verified + reactivate user
      await db.collection("users").doc(uid).update({
        account_status: "active",
        last_login: FieldValue.serverTimestamp(),
      });

      await verificationRef.delete();

      console.log(`✅ Email verified successfully for user: ${uid}`);
      return { success: true, message: "Email verified successfully!" };
    } catch (err) {
      console.error("🔥 [verifyUserEmailOtp] Internal Error:", err);
      throw new HttpsError("internal", err.message);
    }
  }
);
