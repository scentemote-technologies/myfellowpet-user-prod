// functions/index.js

const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const express = require("express");
const cors = require("cors");
const nodemailer = require("nodemailer");
const crypto = require("crypto");

// Initialize Firebase Admin
admin.initializeApp();
const db = admin.firestore();

// 🔐 Define secrets (you already set them in Firebase CLI)
const SMTP_USER = defineSecret("SMTP_USER");
const SMTP_PASS = defineSecret("SMTP_PASS");
const SMTP_HOST = defineSecret("SMTP_HOST");
const SMTP_PORT = defineSecret("SMTP_PORT");

const app = express();
app.use(cors({ origin: true }));
app.use(express.json());

// ── Health checks (for Cloud Run probes) ───────────────
app.get("/", (_req, res) => res.status(200).send("OK"));
app.get("/_ah/health", (_req, res) => res.status(200).send("OK"));

// ── URL builder ─────────────────────────────────────────
const REGION = "asia-south1";
const PROJECT = process.env.GOOGLE_CLOUD_PROJECT;
const FUNCTION_NAME = "emailUpdateService";
const API_PREFIX = "/api";
const makeUrl = (path) =>
  `https://${REGION}-${PROJECT}.cloudfunctions.net/${FUNCTION_NAME}${API_PREFIX}${path}`;

// ── 1) Send verification emails ─────────────────────────
app.post(`${API_PREFIX}/requestEmailChange`, async (req, res) => {
  const { serviceId, newEmail } = req.body;
  if (!serviceId || !newEmail) {
    return res.status(400).send("Missing serviceId or newEmail");
  }

  const svcRef = db.collection("users-sp-boarding").doc(serviceId);
  const svcDoc = await svcRef.get();
  if (!svcDoc.exists) {
    return res.status(404).send("Service not found");
  }
  const oldEmail = svcDoc.data().owner_email;

  // Generate tokens
  const oldToken = crypto.randomBytes(16).toString("hex");
  const newToken = crypto.randomBytes(16).toString("hex");

  // Store them in Firestore
  await svcRef.update({
    emailChange: {
      newEmail,
      oldToken,
      newToken,
      oldVerified: false,
      newVerified: false,
    },
  });

  // Magic links
  const oldLink = makeUrl(`/confirmEmailChange?serviceId=${serviceId}&type=old&token=${oldToken}`);
  const newLink = makeUrl(`/confirmEmailChange?serviceId=${serviceId}&type=new&token=${newToken}`);

  // Create transporter with secrets
  const transporter = nodemailer.createTransport({
    host: SMTP_HOST.value(),
    port: parseInt(SMTP_PORT.value(), 10),
    secure: true,
    auth: {
      user: SMTP_USER.value(),
      pass: SMTP_PASS.value(),
    },
  });

  // Send emails
  await transporter.sendMail({
    from: SMTP_USER.value(),
    to: oldEmail,
    subject: "Confirm Your CURRENT Email",
    html: `<p>Please confirm your <strong>current</strong> email by clicking below:</p>
           <a href="${oldLink}">Confirm Old Email</a>`,
  });

  await transporter.sendMail({
    from: SMTP_USER.value(),
    to: newEmail,
    subject: "Confirm Your NEW Email",
    html: `<p>Please confirm your <strong>new</strong> email by clicking below:</p>
           <a href="${newLink}">Confirm New Email</a>`,
  });

  return res.send("Verification emails sent to old & new addresses.");
});

// ── 2) Magic-link handler ───────────────────────────────
app.get(`${API_PREFIX}/confirmEmailChange`, async (req, res) => {
  const { serviceId, type, token } = req.query;
  if (!serviceId || !type || !token) {
    return res.status(400).send("Missing parameters");
  }

  const svcRef = db.collection("users-sp-boarding").doc(serviceId);
  const doc = await svcRef.get();
  if (!doc.exists) {
    return res.status(404).send("Service not found");
  }

  const ec = doc.data().emailChange || {};
  if (type === "old" && token === ec.oldToken) {
    await svcRef.update({ "emailChange.oldVerified": true });
  } else if (type === "new" && token === ec.newToken) {
    await svcRef.update({ "emailChange.newVerified": true });
  } else {
    return res.status(400).send("Invalid or expired link.");
  }

  return res.send(`
    <html>
      <body style="font-family:Arial,sans-serif;text-align:center;padding:40px">
        <h2>${type === "old" ? "Old" : "New"} email verified!</h2>
        <p>You can now return to the app to finish the update.</p>
      </body>
    </html>
  `);
});

// ── 3) Finalize email update ────────────────────────────
app.post(`${API_PREFIX}/finalizeEmailChange`, async (req, res) => {
  const { serviceId } = req.body;
  if (!serviceId) {
    return res.status(400).send("Missing serviceId");
  }

  const svcRef = db.collection("users-sp-boarding").doc(serviceId);
  const doc = await svcRef.get();
  if (!doc.exists) {
    return res.status(404).send("Service not found");
  }

  const ec = doc.data().emailChange || {};
  if (!ec.oldVerified || !ec.newVerified) {
    return res.status(400).send("Both emails must be verified first.");
  }

  await svcRef.update({
    owner_email: ec.newEmail,
    emailChange: admin.firestore.FieldValue.delete(),
  });

  return res.send("Email updated successfully.");
});

// ── Export function with secrets defined ─────────────────
exports.emailUpdateService = onRequest({
  secrets: [SMTP_USER, SMTP_PASS, SMTP_HOST, SMTP_PORT],
  region: "asia-south1",
}, app);
