/**
 * Firebase Cloud Function (V2) to verify a reCAPTCHA Enterprise token.
 * Uses a single secret (RECAPTCHA_API_KEY) for both siteKey and API key.
 */

import { onRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";
import axios from "axios";
import { initializeApp } from "firebase-admin/app";

// --- Initialization ---
initializeApp();

// 🔐 Define Secrets
// Set these once using:
// firebase functions:secrets:set RECAPTCHA_API_KEY
// firebase functions:secrets:set PROJECT_ID
const RECAPTCHA_API_KEY = defineSecret("RECAPTCHA_API_KEY");
const PROJECT_ID = defineSecret("PROJECT_ID");

// 4️⃣ Define the V2 HTTPS Function
export const verifyRecaptchaToken = onRequest(
  {
    cors: true,
    secrets: [RECAPTCHA_API_KEY, PROJECT_ID],
  },
  async (req, res) => {
    if (req.method !== "POST" || !req.body) {
      logger.error("Invalid request method or missing body.");
      return res
        .status(405)
        .send({ success: false, message: "Method Not Allowed" });
    }

    const { token, action } = req.body;
    if (!token) {
      return res
        .status(400)
        .send({ success: false, message: "reCAPTCHA token is missing." });
    }

    // 🔑 Retrieve secrets securely at runtime
    const apiKey = RECAPTCHA_API_KEY.value();
    const projectId = PROJECT_ID.value();

    // 🔗 Build API request
    const url = `https://recaptchaenterprise.googleapis.com/v1/projects/${projectId}/assessments?key=${apiKey}`;
    const requestBody = {
      event: {
        token: token,
        expectedAction: action || "submit",
        siteKey: apiKey, // ✅ using same key as siteKey
      },
    };

    try {
      logger.info("🔹 Sending token to reCAPTCHA Enterprise API...");
      const response = await axios.post(url, requestBody);
      const assessment = response.data;
      const score = assessment?.riskAnalysis?.score ?? 0;

      logger.info(`✅ Assessment Score for action "${action}": ${score}`);

      if (score >= 0.7) {
        return res.status(200).send({
          success: true,
          score: score,
          message:
            "Key successfully verified and reCAPTCHA Enterprise setup complete.",
        });
      } else {
        return res.status(200).send({
          success: true,
          score: score,
          message:
            "Verification successful, but low trust score detected. Proceed with caution.",
        });
      }
    } catch (error) {
      logger.error("❌ reCAPTCHA API Error during manual setup:", {
        error: error.response?.data || error.message,
      });
      return res.status(500).send({
        success: false,
        message: "Internal verification service failed.",
      });
    }
  }
);
