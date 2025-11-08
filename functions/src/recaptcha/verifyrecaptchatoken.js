/**
 * Firebase Cloud Function (V2) to verify a reCAPTCHA Enterprise token.
 * This function manually completes the key activation step required by App Check.
 * It uses ES Module (ESM) syntax.
 */

// 1. ESM Imports
import { onRequest } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { defineSecret } from 'firebase-functions/params';
import axios from 'axios';
import * as admin from 'firebase-admin';

// Initialize Firebase Admin SDK (needed for basic project context)
import { initializeApp } from "firebase-admin/app";

// --- Initialization ---
initializeApp();
// 2. Define Global Constants
const RECAPTCHA_SITE_KEY = "6LcED64rAAAAABNj8FKEFe3oeK2QdFYWyZoiq4n9";
const PROJECT_ID = "petproject-test-g";

// 3. Define and Access Secret Key
// The secret defined via `firebase functions:secrets:set RECAPTCHA_API_KEY`
const recaptchaApiKey = defineSecret("RECAPTCHA_API_KEY");

// 4. Define the V2 HTTPS Function
export const verifyRecaptchaToken = onRequest({
    // Allow origins and only POST method
    cors: true,
    secrets: [recaptchaApiKey] // Attach the secret
}, async (req, res) => {

    // Check for correct request type
    if (req.method !== 'POST' || !req.body) {
        logger.error("Invalid request method or missing body.");
        return res.status(405).send({ success: false, message: 'Method Not Allowed' });
    }

    const { token, action } = req.body;

    if (!token) {
        return res.status(400).send({ success: false, message: 'reCAPTCHA token is missing.' });
    }

    // Retrieve the secret value securely from the runtime environment
    const API_KEY = recaptchaApiKey.value();

    const url = `https://recaptchaenterprise.googleapis.com/v1/projects/${PROJECT_ID}/assessments?key=${API_KEY}`;

    const requestBody = {
        event: {
            token: token,
            expectedAction: action || 'submit',
            siteKey: RECAPTCHA_SITE_KEY,
        }
    };

    try {
        // 5. External API Call
        const response = await axios.post(url, requestBody);

        const assessment = response.data;
        const score = assessment.riskAnalysis.score;

        logger.info(`Assessment Score for action ${action}: ${score}`);

        // 6. Return success (The primary goal is the successful call, which registers the key)
        if (score >= 0.7) {
            return res.status(200).send({ success: true, score: score, message: "Key successfully verified and setup complete." });
        } else {
            return res.status(200).send({ success: true, score: score, message: "Verification successful, but low score detected." });
        }

    } catch (error) {
        logger.error("ReCAPTCHA API Error during manual setup:", {
            error: error.response?.data || error.message
        });
        // Important: Return 500 status on server error
        return res.status(500).send({ success: false, message: 'Internal verification service failed.' });
    }
});