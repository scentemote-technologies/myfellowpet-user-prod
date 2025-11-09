import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import nodemailer from "nodemailer";
import corsLib from "cors";

const cors = corsLib({ origin: true });
initializeApp();

// 🔐 Define Secrets (you already set them using firebase functions:secrets:set)
const SMTP_USER = defineSecret("SMTP_USER");
const SMTP_PASS = defineSecret("SMTP_PASS");
const SMTP_HOST = defineSecret("SMTP_HOST");
const SMTP_PORT = defineSecret("SMTP_PORT");

// ✅ Function 1: sendDeletionEmail
export const sendDeletionEmail = onRequest(
  { secrets: [SMTP_USER, SMTP_PASS, SMTP_HOST, SMTP_PORT], region: "asia-south1" },
  async (req, res) => {
    cors(req, res, async () => {
      try {
        if (req.method !== "POST") {
          res.status(405).send("Only POST requests allowed");
          return;
        }

        const { serviceId, initiatorEmail } = req.body || {};
        if (!serviceId || !initiatorEmail) {
          res.status(400).send("Missing serviceId or initiatorEmail");
          return;
        }

        // Build “Yes” / “No” links
        const projectRegion = "asia-south1";
        const projectId = process.env.GCLOUD_PROJECT;
        const yesLink = `https://${projectRegion}-${projectId}.cloudfunctions.net/confirmDeletion?serviceId=${serviceId}&action=yes`;
        const noLink = `https://${projectRegion}-${projectId}.cloudfunctions.net/confirmDeletion?serviceId=${serviceId}&action=no`;

        // Create nodemailer transporter using secrets
        const transporter = nodemailer.createTransport({
          host: SMTP_HOST.value(),
          port: parseInt(SMTP_PORT.value(), 10),
          secure: parseInt(SMTP_PORT.value(), 10) === 465,
          auth: {
            user: SMTP_USER.value(),
            pass: SMTP_PASS.value(),
          },
        });

        const mailOptions = {
          from: `"Support Team" <${SMTP_USER.value()}>`,
          to: initiatorEmail,
          subject: `Please Confirm Deletion of Your Service: ${serviceId}`,
          html: `
            <p>Hello ${initiatorEmail},</p>
            <p>You requested to delete Service <strong>${serviceId}</strong>.
               Please confirm your request by clicking one of the buttons below.
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
  }
);

// ✅ Function 2: confirmDeletion
export const confirmDeletion = onRequest(
  { region: "asia-south1" },
  async (req, res) => {
    cors(req, res, async () => {
      try {
        const { serviceId, action } = req.query;
        if (!serviceId || !action) {
          res.status(400).send("Missing serviceId or action");
          return;
        }

        const db = getFirestore();

        if (action === "yes") {
          const boardingRef = db.collection("users-sp-boarding").doc(serviceId);
          await boardingRef.set({ display: false }, { merge: true });
          console.log(`Set display = false for users-sp-boarding/${serviceId}`);
        }

        await db.collection("deletionRequests").doc(serviceId).set({
          action: action === "yes" ? "confirmed" : "declined",
          timestamp: FieldValue.serverTimestamp(),
        });

        const message =
          action === "yes"
            ? "You have confirmed deletion. Your service will be hidden."
            : "Deletion canceled. Your service remains active.";

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
  }
);
