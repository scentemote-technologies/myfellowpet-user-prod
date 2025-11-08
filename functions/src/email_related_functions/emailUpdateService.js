// functions/index.js

const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const express = require("express");
const cors = require("cors");
const nodemailer = require("nodemailer");
const crypto = require("crypto");

admin.initializeApp();
const db = admin.firestore();

// ── SMTP creds from GCP env vars ──────────────────────────────────────────────
const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: Number(process.env.SMTP_PORT),
  secure: true,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
  },
});

const app = express();
app.use(cors({origin: true}));
app.use(express.json());

// ── Health‐check endpoints (Cloud Run probes `/` by default) ────────────────
app.get("/", (_req, res) => res.status(200).send("OK"));
app.get("/_ah/health", (_req, res) => res.status(200).send("OK"));

// ── URL builder ───────────────────────────────────────────────────────────────
const REGION = "us-central1";
const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "petproject-test-g";
const FUNCTION_NAME = "emailUpdateService";
const API_PREFIX = "/api";
const makeUrl = (path) =>
  `https://${REGION}-${PROJECT}.cloudfunctions.net/${FUNCTION_NAME}${API_PREFIX}${path}`;

// ── 1) Send verification emails ───────────────────────────────────────────────
app.post(`${API_PREFIX}/requestEmailChange`, async (req, res) => {
  const {serviceId, newEmail} = req.body;
  if (!serviceId || !newEmail) {
    return res.status(400).send("Missing serviceId or newEmail");
  }

  const svcRef = db.collection("users-sp-boarding").doc(serviceId);
  const svcDoc = await svcRef.get();
  if (!svcDoc.exists) {
    return res.status(404).send("Service not found");
  }
  const oldEmail = svcDoc.data().owner_email;

  // generate one-time tokens
  const oldToken = crypto.randomBytes(16).toString("hex");
  const newToken = crypto.randomBytes(16).toString("hex");

  // store them in Firestore
  await svcRef.update({
    emailChange: {
      newEmail,
      oldToken,
      newToken,
      oldVerified: false,
      newVerified: false,
    },
  });

  // build the magic-links
  const oldLink = makeUrl(`/confirmEmailChange?serviceId=${serviceId}&type=old&token=${oldToken}`);
  const newLink = makeUrl(`/confirmEmailChange?serviceId=${serviceId}&type=new&token=${newToken}`);

  // send to old address
  await transporter.sendMail({
    from:    process.env.SMTP_USER,
    to:      oldEmail,
    subject: "Confirm Your CURRENT Email",
    html:    `<p>Please confirm your <strong>current</strong> email by clicking below:</p>
              <a href="${oldLink}">Confirm Old Email</a>`,
  });

  // send to new address
  await transporter.sendMail({
    from:    process.env.SMTP_USER,
    to:      newEmail,
    subject: "Confirm Your NEW Email",
    html:    `<p>Please confirm your <strong>new</strong> email by clicking below:</p>
              <a href="${newLink}">Confirm New Email</a>`,
  });

  return res.send("Verification emails sent to old & new addresses.");
});

// ── 2) Magic-link handler ─────────────────────────────────────────────────────
app.get(`${API_PREFIX}/confirmEmailChange`, async (req, res) => {
  const {serviceId, type, token} = req.query;
  if (!serviceId || !type || !token) {
    return res.status(400).send("Missing parameters");
  }

  const svcRef = db.collection("users-sp-boarding").doc(serviceId);
  const doc    = await svcRef.get();
  if (!doc.exists) {
    return res.status(404).send("Service not found");
  }

  const ec = doc.data().emailChange || {};
  if (type === "old" && token === ec.oldToken) {
    await svcRef.update({"emailChange.oldVerified": true});
  } else if (type === "new" && token === ec.newToken) {
    await svcRef.update({"emailChange.newVerified": true});
  } else {
    return res.status(400).send("Invalid or expired link.");
  }

  // confirmation page
  return res.send(`
    <html>
      <body style="font-family:Arial,sans-serif;text-align:center;padding:40px">
        <h2>${type === "old" ? "Old" : "New"} email verified!</h2>
        <p>You can now return to the app to finish the update.</p>
      </body>
    </html>
  `);
});

// ── 3) Finalize email update ─────────────────────────────────────────────────
app.post(`${API_PREFIX}/finalizeEmailChange`, async (req, res) => {
  const {serviceId} = req.body;
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

  // commit the new email
  await svcRef.update({
    owner_email: ec.newEmail,
    emailChange: admin.firestore.FieldValue.delete(),
  });

  return res.send("Email updated successfully.");
});

// ── Export under the new name ────────────────────────────────────────────────
exports.emailUpdateService = onRequest(app);
