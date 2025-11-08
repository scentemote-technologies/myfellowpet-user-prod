const functions=require("firebase-functions");
const admin=require("firebase-admin");
const nodemailer=require("nodemailer");
const cors=require("cors")({origin: true});

admin.initializeApp();

// Read GoDaddy SMTP settings from Firebase config:
//   firebase functions:config:set \
//     smtp.user="notification@companyname.com" \
//     smtp.pass="<your_godaddy_email_password>" \
//     smtp.host="smtpout.secureserver.net" \
//     smtp.port="465"
const SMTP_USER = functions.config().smtp.user;
const SMTP_PASS = functions.config().smtp.pass;
const SMTP_HOST = functions.config().smtp.host;
const SMTP_PORT = parseInt(functions.config().smtp.port || "465", 10);

if (!SMTP_USER || !SMTP_PASS || !SMTP_HOST || !SMTP_PORT) {
  console.error(
    "Missing SMTP settings. Run:\n" +
    "  firebase functions:config:set \\\n" +
    "    smtp.user=\"notification@companyname.com\" \\\n" +
    "    smtp.pass=\"<your_password>\" \\\n" +
    "    smtp.host=\"smtpout.secureserver.net\" \\\n" +
    "    smtp.port=\"465\"",
  );
}

const transporter = nodemailer.createTransport({
  host: SMTP_HOST,
  port: SMTP_PORT,
  secure: SMTP_PORT === 465, // true for SSL on port 465, false for TLS on 587
  auth: {
    user: SMTP_USER,
    pass: SMTP_PASS,
  },
});


/**
 * 1) sendDeletionEmail
 *    - Expects a POST with JSON body: { serviceId, initiatorEmail }
 *    - Sends an email *to* initiatorEmail, informing them that their deletion request
 *      is under review and providing “Yes/No” buttons to confirm or cancel.
 */
exports.sendDeletionEmail = functions.https.onRequest((req, res) => {
  cors(req, res, async () => {
    try {
      if (req.method !== "POST") {
        res.status(405).send("Only POST requests allowed");
        return;
      }

      const {serviceId, initiatorEmail} = req.body || {};
      if (!serviceId || !initiatorEmail) {
        res.status(400).send("Missing serviceId or initiatorEmail");
        return;
      }

      // Build “Yes” / “No” links that point back to confirmDeletion
      const projectRegion = "us-central1";// adjust if needed
      const projectId = process.env.GCLOUD_PROJECT;
      const yesLink = `https://${projectRegion}-${projectId}.cloudfunctions.net/confirmDeletion?serviceId=${serviceId}&action=yes`;
      const noLink = `https://${projectRegion}-${projectId}.cloudfunctions.net/confirmDeletion?serviceId=${serviceId}&action=no`;

      // Compose an HTML email addressed to initiatorEmail
      const mailOptions = {
        from: `"Support Team" <${SMTP_USER}>`,
        to: initiatorEmail,
        subject: `Please Confirm Deletion of Your Service: ${serviceId}`,
        html: `
          <p>Hello ${initiatorEmail},</p>
          <p>You requested to delete Service <strong>${serviceId}</strong>.
             Please confirm your own request by clicking one of the buttons below.
             <strong>This action cannot be undone.</strong></p>
          <p>
            <a href="${yesLink}" style="
                display:inline-block;
                padding:12px 20px;
                background:#d9534f;
                color:white;
                text-decoration:none;
                border-radius:4px;
              ">Yes, delete my service</a>
            &nbsp;&nbsp;
            <a href="${noLink}" style="
                display:inline-block;
                padding:12px 20px;
                background:#5bc0de;
                color:white;
                text-decoration:none;
                border-radius:4px;
              ">No, keep my service</a>
          </p>
          <p>If you did not initiate this request, simply ignore this email.</p>
          <p>Thank you,<br/>The Support Team</p>
        `,
      };

      await transporter.sendMail(mailOptions);
      console.log(`Deletion confirmation email sent to ${initiatorEmail} for service ${serviceId}`);
      res.status(200).send("Confirmation email sent");
    } catch (err) {
      console.error("Error in sendDeletionEmail:", err);
      res.status(500).send("Internal Server Error");
    }
  });
});


/**
 * 2) confirmDeletion
 *    - Triggered when the user clicks “Yes” or “No” in the email.
 *    - If action==="yes", updates users-sp-boarding/{serviceId}.display = false.
 *    - Records { action, timestamp } under deletionRequests/{serviceId}.
 */
exports.confirmDeletion = functions.https.onRequest((req, res) => {
  cors(req, res, async () => {
    try {
      const {serviceId, action} = req.query;
      if (!serviceId || !action) {
        res.status(400).send("Missing serviceId or action");
        return;
      }

      const db = admin.firestore();

      if (action === "yes") {
        const boardingRef = db.collection("users-sp-boarding").doc(serviceId);
        await boardingRef.set({display: false}, {merge: true});
        console.log(`Set display = false for users-sp-boarding/${serviceId}`);
      }

      await db
        .collection("deletionRequests")
        .doc(serviceId)
        .set({
          action: action === "yes" ? "confirmed" : "declined",
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

      const message = action === "yes" ?
        "You have confirmed deletion. Your service will be hidden." :
        "Deletion canceled. Your service remains active.";

      res.status(200).send(`
        <html>
          <body style="font-family: Arial, sans-serif; text-align: center; padding: 40px;">
            <h2>${message}</h2>
          </body>
        </html>
      `);
    } catch (err) {
      console.error("Error in confirmDeletion:", err);
      res.status(500).send("Internal Server Error");
    }
  });
});
