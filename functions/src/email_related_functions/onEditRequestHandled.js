const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const nodemailer = require("nodemailer");

// 🔥 Initialize Firebase Admin
initializeApp();
const db = getFirestore();

// 🔐 Define secrets (you already set these globally)
const SMTP_USER = defineSecret("SMTP_USER");
const SMTP_PASS = defineSecret("SMTP_PASS");
const SMTP_HOST = defineSecret("SMTP_HOST");
const SMTP_PORT = defineSecret("SMTP_PORT");

// ✅ Function: onEditRequestHandled
exports.onEditRequestHandled = onDocumentUpdated(
  {
    region: "europe-west1", // keep your preferred region
    secrets: [SMTP_USER, SMTP_PASS, SMTP_HOST, SMTP_PORT],
    document: "users-sp-boarding/{serviceId}/profile_edit_requests/{reqId}",
  },
  async (event) => {
    const before = event.data?.before?.data() || {};
    const after = event.data?.after?.data() || {};

    // Trigger only when handled changes from false → true
    if (before.handled || !after.handled) {
      return null;
    }

    const { serviceId, reqId } = event.params;

    // 🔹 Fetch parent service document
    const serviceSnap = await db.doc(`users-sp-boarding/${serviceId}`).get();
    if (!serviceSnap.exists) {
      console.error(`Service ${serviceId} not found — can't email owner`);
      return null;
    }

    const ownerEmail = serviceSnap.get("owner_email");
    if (!ownerEmail) {
      console.error(`Service ${serviceId} has no owner_email`);
      return null;
    }

    // 🔹 Create transporter using secrets
    const transporter = nodemailer.createTransport({
      host: SMTP_HOST.value(),
      port: parseInt(SMTP_PORT.value(), 10),
      secure: true,
      auth: {
        user: SMTP_USER.value(),
        pass: SMTP_PASS.value(),
      },
    });

    // 🔹 Build the email
    const mailOptions = {
      from: `"MyFellowPet Notifications" <${SMTP_USER.value()}>`,
      to: ownerEmail,
      subject: `Your service (${serviceId}) edit request has been processed`,
      text: `
Hi there,

Your recent edit request (ID: ${reqId}) for service "${serviceId}" has been handled by the admin.

Approved fields: ${(after.approvedFields || []).join(", ") || "None"}
Rejected fields: ${Object.entries(after.rejectedFields || {})
        .map(([k, v]) => `${k} (reason: ${v})`)
        .join("; ") || "None"}

Thanks,
Support Team
      `.trim(),
    };

    // 🔹 Send the email
    try {
      await transporter.sendMail(mailOptions);
      console.log(`✉️ Email sent to ${ownerEmail} about request ${reqId}`);
    } catch (err) {
      console.error("❌ Error sending email:", err);
    }

    return null;
  }
);
