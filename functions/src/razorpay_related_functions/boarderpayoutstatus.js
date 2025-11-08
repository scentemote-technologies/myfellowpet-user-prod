import { onRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import cors from "cors";
import admin from "firebase-admin";

admin.initializeApp();
const corsHandler = cors({ origin: true });

export const BoarderPayoutStatus = onRequest((req, res) => {
  return corsHandler(req, res, async () => {
    const { serviceProviderId, orderId, payoutId, event } = req.body;
    logger.info("💡 Webhook received", { serviceProviderId, orderId, payoutId, event });

    if (!serviceProviderId || !orderId || !payoutId || !event) {
      res.status(400).send("Missing webhook payload");
      return;
    }

    try {
      const docRef = admin
        .firestore()
        .collection("users-sp-boarding")
        .doc(serviceProviderId)
        .collection("service_request_boarding")
        .doc(orderId);

      const docSnap = await docRef.get();
      if (!docSnap.exists) throw new Error("Order not found");

      await docRef.update({
        "payout_info.status":    event.payload.status,
        "payout_info.updatedAt": admin.firestore.FieldValue.serverTimestamp()
      });

      res.status(200).send("OK");
    } catch (e) {
      logger.error("❌ Webhook processing failed", e);
      res.status(500).send(e.message);
    }
  });
});
