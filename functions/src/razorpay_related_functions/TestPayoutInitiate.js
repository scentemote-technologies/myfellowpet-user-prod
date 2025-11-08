import { onRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import cors from "cors";
import fetch from "node-fetch"; // ✅ Add this if not already imported
import admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

admin.initializeApp();


const corsHandler = cors({ origin: true });

const RZP_KEY_ID = "rzp_test_RZl8dNUzIDfwFD";
const RZP_KEY_SECRET = "fswZ1n6l4gS7Ad6Dv0wouKUb";

export const v2initiatePayout = onRequest((req, res) => {
  return corsHandler(req, res, async () => {
    logger.info("💡 v2initiatePayout invoked", { body: req.body });

    try {
      const { serviceProviderId, orderId, fundAccountId, amount } = req.body;

      if (!serviceProviderId || !orderId || !fundAccountId || !amount) {
        logger.error("🚨 Missing parameters", { serviceProviderId, orderId, fundAccountId, amount });
        res.status(400).send("Missing parameters");
        return;
      }

      logger.info("🚀 Creating RazorpayX Payout", { fundAccountId, amount });

      // Direct API call to RazorpayX
      const response = await fetch("https://api.razorpay.com/v1/payouts", {
        method: "POST",
        headers: {
          "Authorization": "Basic " + Buffer.from(`${RZP_KEY_ID}:${RZP_KEY_SECRET}`).toString("base64"),
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          account_number: "2323230078245300", // Your virtual account number
          fund_account_id: fundAccountId,
          amount: amount, // in paise
          currency: "INR",
          mode: "IMPS",
          purpose: "payout",
          queue_if_low_balance: true,
          narration: `Payout`,
          reference_id: orderId,
        }),
      });

      const payoutResult = await response.json();

      if (!response.ok) {
        logger.error("❌ RazorpayX API Error", payoutResult);
        res.status(500).json({ success: false, error: payoutResult });
        return;
      }

      logger.info("✅ Payout created successfully", payoutResult);
      // 🔥 Save payout info in Firestore for webhook matching
      try {
        // Save payout info safely even if completed_orders doc doesn't exist yet
        const completedRef = admin.firestore()
          .collection('users-sp-boarding')
          .doc(serviceProviderId)
          .collection('completed_orders')
          .doc(orderId);

        const completedSnap = await completedRef.get();

        if (completedSnap.exists) {
          // ✅ If completed order already exists → just update it
           await completedRef.update({
             payout_id: payoutResult.id,
             payout_status: payoutResult.status || 'processing',
             payout_done: false,
             payout_created_at: admin.firestore.FieldValue.serverTimestamp(),
           });
           logger.info(`✅ Firestore updated for ${orderId} (completed_orders already exists).`);
        } else {
            // ⚠️ If it doesn't exist yet → temporarily save in a separate safe place
            await admin.firestore()
              .collection('pending_payouts')
              .doc(orderId)
              .set({
                serviceProviderId,
                payout_id: payoutResult.id,
                payout_status: payoutResult.status || 'processing',
                payout_done: false,
                payout_created_at: admin.firestore.FieldValue.serverTimestamp(),
              });
            logger.info(`💾 Saved payout info for ${orderId} to pending_payouts (waiting for completed_orders).`);
        }


        logger.info(`✅ Firestore updated for ${orderId} with payout_id ${payoutResult.id}`);
      } catch (err) {
        logger.error("⚠️ Failed to update Firestore with payout_id", err);
      }

      res.status(200).json({ success: true, payoutId: payoutResult.id, data: payoutResult });

    } catch (err) {
      logger.error("🔥 Payout error", err);
      res.status(500).json({ success: false, error: err.message });
    }
  });
});


export const attachPendingPayout = onDocumentWritten(
  "users-sp-boarding/{spId}/completed_orders/{orderId}",
  async (event) => {
    const { spId, orderId } = event.params;

    // 1️⃣ Check if a pending payout exists
    const pendingRef = admin.firestore().collection("pending_payouts").doc(orderId);
    const pendingSnap = await pendingRef.get();

    if (!pendingSnap.exists) {
      logger.info(`ℹ️ No pending payout found for ${orderId}`);
      return;
    }

    const payoutData = pendingSnap.data();

    // 2️⃣ Attach payout info to completed_orders doc
    await event.data.ref.update({
      payout_id: payoutData.payout_id,
      payout_status: payoutData.payout_status,
      payout_done: payoutData.payout_done,
      payout_created_at: payoutData.payout_created_at,
    });

    // 3️⃣ Delete pending record to keep DB clean
    await pendingRef.delete();

    logger.info(`✅ Attached pending payout to completed_orders/${orderId}`);
  }
);