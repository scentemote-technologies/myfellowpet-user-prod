import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import cors from "cors";
import fetch from "node-fetch"; // ✅ Ensure this is installed
import admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

admin.initializeApp();

const corsHandler = cors({ origin: true });

// 🔐 Secure Razorpay test payout keys via Firebase Secrets
const RZP_KEY = defineSecret("RAZORPAY_TEST_PAYOUT_KEY");
const RZP_SECRET = defineSecret("RAZORPAY_TEST_PAYOUT_SECRET");

// ✅ Function 1: Initiate Payout
export const v2initiatePayout = onRequest(
  {
    region: "asia-south1",
    secrets: [RZP_KEY, RZP_SECRET],
  },
  (req, res) => {
    return corsHandler(req, res, async () => {
      logger.info("💡 v2initiatePayout invoked", { body: req.body });

      try {
        const { serviceProviderId, orderId, fundAccountId, amount } = req.body;

        if (!serviceProviderId || !orderId || !fundAccountId || !amount) {
          logger.error("🚨 Missing parameters", {
            serviceProviderId,
            orderId,
            fundAccountId,
            amount,
          });
          res.status(400).send("Missing parameters");
          return;
        }

        logger.info("🚀 Creating RazorpayX Payout", { fundAccountId, amount });

        // 🔹 Make payout API call
        const response = await fetch("https://api.razorpay.com/v1/payouts", {
          method: "POST",
          headers: {
            "Authorization":
              "Basic " +
              Buffer.from(`${RZP_KEY.value()}:${RZP_SECRET.value()}`).toString("base64"),
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            account_number: "2323230078245300", // Your virtual account number
            fund_account_id: fundAccountId,
            amount: amount, // Amount in paise
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
          const completedRef = admin
            .firestore()
            .collection("users-sp-boarding")
            .doc(serviceProviderId)
            .collection("completed_orders")
            .doc(orderId);

          const completedSnap = await completedRef.get();

          if (completedSnap.exists) {
            // ✅ Update existing completed order
            await completedRef.update({
              payout_id: payoutResult.id,
              payout_status: payoutResult.status || "processing",
              payout_done: false,
              payout_created_at: admin.firestore.FieldValue.serverTimestamp(),
            });
            logger.info(`✅ Firestore updated for ${orderId} (completed_orders already exists).`);
          } else {
            // ⚠️ Save in pending_payouts if order doc not created yet
            await admin
              .firestore()
              .collection("pending_payouts")
              .doc(orderId)
              .set({
                serviceProviderId,
                payout_id: payoutResult.id,
                payout_status: payoutResult.status || "processing",
                payout_done: false,
                payout_created_at: admin.firestore.FieldValue.serverTimestamp(),
              });
            logger.info(
              `💾 Saved payout info for ${orderId} to pending_payouts (waiting for completed_orders).`
            );
          }

          logger.info(
            `✅ Firestore updated for ${orderId} with payout_id ${payoutResult.id}`
          );
        } catch (err) {
          logger.error("⚠️ Failed to update Firestore with payout_id", err);
        }

        res.status(200).json({
          success: true,
          payoutId: payoutResult.id,
          data: payoutResult,
        });
      } catch (err) {
        logger.error("🔥 Payout error", err);
        res.status(500).json({ success: false, error: err.message });
      }
    });
  }
);

// ✅ Function 2: Attach Pending Payout once order doc exists
export const attachPendingPayout = onDocumentWritten(
  "users-sp-boarding/{spId}/completed_orders/{orderId}",
  async (event) => {
    const { spId, orderId } = event.params;

    // 1️⃣ Check if pending payout exists
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

    // 3️⃣ Delete pending record
    await pendingRef.delete();

    logger.info(`✅ Attached pending payout to completed_orders/${orderId}`);
  }
);
