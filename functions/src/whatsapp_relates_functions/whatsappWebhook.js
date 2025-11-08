// functions/index.js

const {onRequest} = require("firebase-functions/v2/https");
const express = require("express");

const app = express();
app.use(express.json());

// Pull your verify token from env
// (we’ll inject this at deploy time)
const VERIFY_TOKEN = process.env.WHATSAPP_VERIFY_TOKEN;

app.get("/whatsapp-webhook", (req, res) => {
  const mode = req.query["hub.mode"];
  const token = req.query["hub.verify_token"];
  const challenge = req.query["hub.challenge"];

  if (mode === "subscribe" && token === VERIFY_TOKEN) {
    console.log("✅ WEBHOOK_VERIFIED");
    return res.status(200).send(challenge);
  }
  console.error("❌ WEBHOOK_VERIFICATION_FAILED");
  return res.sendStatus(403);
});

app.post("/whatsapp-webhook", (req, res) => {
  const body = req.body;

  if (body.object && Array.isArray(body.entry)) {
    body.entry.forEach((entry) => {
      (entry.changes || []).forEach((change) => {
        const msgs = (change.value && change.value.messages) || [];
        msgs.forEach((msg) => {
          const incomingText = msg.text && msg.text.body;
          console.log(`📩 From ${msg.from}:`, incomingText);
          // → TODO: call your sendMessage(msg.from, reply) here
        });
      });
    });
    return res.status(200).send("EVENT_RECEIVED");
  }

  return res.sendStatus(404);
});

exports.whatsappWebhook = onRequest(
    {region: "asia-south1"},
    app,
);
