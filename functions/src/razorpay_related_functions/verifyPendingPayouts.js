import { onSchedule } from "firebase-functions/v2/scheduler";
import fetch from "node-fetch";

export const verifyPendingPayouts = onSchedule(
  {
    schedule: "every 30 minutes",
    region: "asia-south1",
  },
  async (event) => {
    const db = admin.firestore();
    const pendingSnap = await db
      .collectionGroup("completed_orders")
      .where("payout_done", "==", false)
      .get();

    if (pendingSnap.empty) {
      logger.info("✅ No pending payouts found");
      return;
    }

    logger.info(`🔍 Checking ${pendingSnap.size} pending payouts...`);

    for (const doc of pendingSnap.docs) {
      const data = doc.data();
      const payoutId = data.payout_id;

      if (!payoutId) continue;

      try {
        const res = await fetch(`https://api.razorpay.com/v1/payouts/${payoutId}`, {
          headers: {
            "Authorization":
              "Basic " +
              Buffer.from(`${RZP_KEY_ID}:${RZP_KEY_SECRET}`).toString("base64"),
          },
        });

        const result = await res.json();

        if (!res.ok) {
          logger.error("❌ Razorpay API error", result);
          continue;
        }

        const status = result.status;

        await doc.ref.update({
          payout_status: status,
          payout_done: status === "processed",
          payout_updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        logger.info(`✅ Updated ${payoutId} → ${status}`);
      } catch (err) {
        logger.error(`⚠️ Error verifying payout ${payoutId}`, err);
      }
    }

    logger.info("🎯 Payout verification complete");
  }
);
