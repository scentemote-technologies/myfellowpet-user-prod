const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const axios = require("axios");
const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");

admin.initializeApp();

// --- Define Secrets ---
const WHATSAPP_ACCESS_TOKEN = defineSecret("WHATSAPP_ACCESS_TOKEN");
const WHATSAPP_PHONE_NUMBER_ID = defineSecret("WHATSAPP_PHONE_NUMBER_ID");

// --- Trigger when a booking is moved to completed_orders and isEndPinUsed = true ---
exports.UserBoardingOrderDone = onDocumentCreated(
  {
    region: "asia-south1",
    document: "users-sp-boarding/{serviceId}/completed_orders/{bookingId}",
    secrets: [WHATSAPP_ACCESS_TOKEN, WHATSAPP_PHONE_NUMBER_ID],
    maxInstances: 2,
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const bookingId = event.params.bookingId;
    const docRef = event.data.ref;

    // Only trigger if isEndPinUsed is true
    if (data.isEndPinUsed !== true) {
      logger.info(`Skipping ${bookingId}: isEndPinUsed is not true`);
      return;
    }

    // Avoid duplicate sends
    if (data.wa_order_done_sent === true) {
      logger.info(`Skipping ${bookingId}: WA order done already sent`);
      return;
    }
    if (data.wa_order_done_in_progress === true) {
      logger.info(`Skipping ${bookingId}: Send already in progress`);
      return;
    }

    // Set "in-progress" lock
    await docRef.update({
      wa_order_done_in_progress: true,
      wa_order_done_in_progress_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info(`📍 Sending WhatsApp 'order done' message for ${bookingId}...`);

    const recipientNumber = data.phone_number;
    const customerName = data.user_name || "Pet Parent";
    const boardingPartner = data.shopName || "Boarding Partner";

    const accessToken = WHATSAPP_ACCESS_TOKEN.value();
    const phoneNumberId = WHATSAPP_PHONE_NUMBER_ID.value();
    const url = `https://graph.facebook.com/v23.0/${phoneNumberId}/messages`;

    const payload = {
      messaging_product: "whatsapp",
      to: recipientNumber,
      type: "template",
      template: {
        name: "user_boarding_order_done",
        language: { code: "en_US" },
        components: [
          {
            type: "body",
            parameters: [
              { type: "text", text: customerName },
              { type: "text", text: boardingPartner },
            ],
          },
        ],
      },
    };

    try {
      const response = await axios.post(url, payload, {
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
      });

      logger.info(`✅ WhatsApp 'order done' message sent for ${bookingId}`, response.data);

      await docRef.update({
        wa_order_done_sent: true,
        wa_order_done_sent_at: admin.firestore.FieldValue.serverTimestamp(),
        wa_order_done_failed: admin.firestore.FieldValue.delete(),
        wa_order_done_failure_reason: admin.firestore.FieldValue.delete(),
        wa_order_done_in_progress: false,
      });

    } catch (error) {
      const errMsg = error.response?.data?.error?.message || error.message;
      logger.error(`❌ WhatsApp send failed for ${bookingId}:`, errMsg);

      await docRef.update({
        wa_order_done_sent: false,
        wa_order_done_failed: true,
        wa_order_done_failure_reason: errMsg,
        wa_order_done_in_progress: false,
        wa_order_done_last_attempt_at: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
);
