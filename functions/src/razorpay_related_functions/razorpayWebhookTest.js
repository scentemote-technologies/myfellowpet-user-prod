const functions = require("firebase-functions/v2");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const crypto = require("crypto");

admin.initializeApp();

exports.razorpayWebhookTest = functions.https.onRequest(
  {
    region: "asia-south1",
    cors: true,
    secrets: ["RAZORPAY_WEBHOOK_SECRET_TEST"],
  },
  async (req, res) => {
    try {
      const secret = process.env.RAZORPAY_WEBHOOK_SECRET_TEST;
      const signature = req.get("x-razorpay-signature");
      const rawBody = req.rawBody ? req.rawBody.toString() : JSON.stringify(req.body || {});

      const expected = crypto.createHmac("sha256", secret).update(rawBody).digest("hex");
      if (expected !== signature) {
        logger.error("❌ Invalid Razorpay signature");
        return res.status(400).send("Invalid signature");
      }

      const event = req.body.event;
      const payout = req.body?.payload?.payout?.entity;
      if (!payout) return res.status(200).send("No payout entity");

      const payoutId = payout.id;
      const status = payout.status;

      logger.info(`✅ Razorpay TEST webhook: ${event} for ${payoutId} (${status})`);

      await admin.firestore().collection("webhook_logs").add({
        source: "razorpay_test",
        event,
        payout_id: payoutId,
        status,
        received_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      const snap = await admin
        .firestore()
        .collectionGroup("completed_orders")
        .where("payout_id", "==", payoutId)
        .get();

      if (snap.empty) {
        logger.warn(`⚠️ No Firestore doc found for payout ${payoutId}`);
        return res.status(200).send("OK (no matching doc)");
      }

      const batch = admin.firestore().batch();
      snap.forEach((doc) => {
        batch.update(doc.ref, {
          payout_status: status,
          payout_done: status === "processed",
          payout_updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
      await batch.commit();

      res.status(200).send("OK");
    } catch (err) {
      logger.error("Webhook error", err);
      res.status(500).send("Server error");
    }
  }
);
