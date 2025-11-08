const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();

// pull SMTP settings from your config
const {user: SMTP_USER, pass: SMTP_PASS, host: SMTP_HOST, port: SMTP_PORT} =
  functions.config().smtp || {};

if (!SMTP_USER || !SMTP_PASS || !SMTP_HOST || !SMTP_PORT) {
  console.error("⚠️ Missing SMTP config! Run `firebase functions:config:set smtp.*`");
}

// set up a reusable transporter
const transporter = nodemailer.createTransport({
  host: SMTP_HOST,
  port: SMTP_PORT,
  secure: true,
  auth: {
    user: SMTP_USER,
    pass: SMTP_PASS,
  },
});

/**
 * When an edit‐request doc under users-sp-boarding/{serviceId}/profile_edit_requests/{reqId}
 * gets updated to handled:true, send a notification to owner_email on the parent service doc.
 */
exports.onEditRequestHandled = functions
  .region("europe-west1")// pick a region that’s healthy
  .firestore
  .document("users-sp-boarding/{serviceId}/profile_edit_requests/{reqId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    // only fire when handled has just flipped to true
    if (!before.handled && after.handled) {
      const {serviceId, reqId} = context.params;

      // fetch the parent service doc to grab owner_email
      const serviceSnap = await admin
        .firestore()
        .doc(`users-sp-boarding/${serviceId}`)
        .get();

      if (!serviceSnap.exists) {
        console.error(`Service ${serviceId} not found, can't email owner`);
        return null;
      }

      const ownerEmail = serviceSnap.get("owner_email");
      if (!ownerEmail) {
        console.error(`Service ${serviceId} has no owner_email field`);
        return null;
      }

      // compose a simple email
      const mailOptions = {
        from: `"MyFellowPet Notifications" <${SMTP_USER}>`,
        to: ownerEmail,
        subject: `Your service (${serviceId}) edit request has been processed`,
        text: `
Hi there,

Your recent edit request (ID: ${reqId}) for service "${serviceId}" has been handled by the admin.

Approved fields:   ${ (after.approvedFields || []).join(", ") }
Rejected fields:   ${ Object.entries(after.rejectedFields || {})
                             .map(([k, v]) => `${k} (reason: ${v})`).join("; ") }

Thanks,
Support Team
        `.trim(),
      };

      // send it!
      try {
        await transporter.sendMail(mailOptions);
        console.log(`✉️ Email sent to ${ownerEmail} about request ${reqId}`);
      } catch (err) {
        console.error("Error sending email:", err);
      }
    }

    return null;
  });
