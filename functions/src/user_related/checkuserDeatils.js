const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");
const crypto = require("crypto");

initializeApp();
const db = getFirestore();
const auth = getAuth();

exports.checkUserDetails = onRequest({ cors: true }, async (req, res) => {
  try {
    const { idToken, pin, emailOtp } = req.query;

    if (!idToken) {
      return res.status(400).json({
        success: false,
        error:
          "Missing Firebase ID token. Please sign in with OTP and provide the token.",
      });
    }

    // ✅ Verify ID Token using Firebase Auth
    const decoded = await auth.verifyIdToken(idToken);
    const phoneNumber = decoded.phone_number;

    if (!phoneNumber) {
      return res.status(400).json({
        success: false,
        error: "Invalid token — phone number not found in user record.",
      });
    }

    // 🔍 Find user in Firestore by UID or phone
    const userDoc = await db.collection("users").doc(decoded.uid).get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "No user found in Firestore for this phone.",
      });
    }

    const userData = userDoc.data();
    const userId = userDoc.id;

    // 🔒 Account locked check
    if (userData.account_status === "locked") {
      if (pin) {
        const enteredHash = crypto.createHash("sha256").update(pin).digest("hex");
        if (enteredHash === userData.pin_hashed) {
          await db.collection("users").doc(userId).update({
            account_status: "active",
            last_login: new Date(),
          });
        } else {
          return res.status(403).json({
            success: false,
            accountStatus: "locked",
            methodRequired: "pin",
            message: "Incorrect PIN.",
          });
        }
      } else if (emailOtp) {
        // In production, verify with a real OTP email system (sendGrid/Mailgun etc.)
        // Placeholder for actual OTP verification service
        return res.status(403).json({
          success: false,
          accountStatus: "locked",
          methodRequired: "email",
          message: "Please verify your email OTP.",
        });
      } else {
        return res.status(403).json({
          success: false,
          accountStatus: "locked",
          message:
            "Account locked. Please verify using your 6-digit PIN or email OTP.",
        });
      }
    }

    // 🐶 Fetch user's pets if active
    const petsSnap = await db
      .collection("users")
      .doc(userId)
      .collection("users-pets")
      .get();

    const pets = petsSnap.docs.map((doc) => ({
      petId: doc.id,
      ...doc.data(),
    }));

    // ✅ Success response
    return res.status(200).json({
      success: true,
      user: {
        uid: userId,
        name: userData.name || null,
        phone: userData.phone,
        accountStatus: userData.account_status || "active",
        lastLogin: userData.last_login || null,
      },
      pets,
    });
  } catch (error) {
    console.error("Error in checkUserDetails:", error);
    return res.status(500).json({ success: false, error: error.message });
  }
});
