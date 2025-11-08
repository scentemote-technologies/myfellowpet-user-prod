const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const axios = require("axios");
const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");

admin.initializeApp();

// --- Define Secrets ---
const WHATSAPP_ACCESS_TOKEN = defineSecret("WHATSAPP_ACCESS_TOKEN");
const WHATSAPP_PHONE_NUMBER_ID = defineSecret("WHATSAPP_PHONE_NUMBER_ID");

// --- Trigger when order_status becomes 'confirmed' ---
exports.sendUserBoardingBookingConfirmation = onDocumentUpdated(
  {
    region: "asia-south1",
    document: "users-sp-boarding/{serviceId}/service_request_boarding/{bookingId}",
    secrets: [WHATSAPP_ACCESS_TOKEN, WHATSAPP_PHONE_NUMBER_ID],
    maxInstances: 2,
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();

    if (!before || !after) return;

    const bookingId = event.params.bookingId;
    const docRef = event.data.after.ref;

    // ✅ Trigger only when order_status changes to "confirmed"
    if (before.order_status === after.order_status || after.order_status !== "confirmed") {
      logger.info(`No trigger for ${bookingId}: order_status not changed to 'confirmed'`);
      return;
    }

    logger.info(`🎉 Booking confirmed for ${bookingId}. Sending WhatsApp message...`);

    const recipientNumber = after.phone_number;
    const customerName = after.user_name || "Pet Parent";
    const orderId = after.order_id || bookingId;
    const boardingPartner = after.shopName || "Boarding Partner";
    const pets = (after.pet_name || []).join(", ");

    const formattedDates = (after.selectedDates || [])
      .map((ts) => ts.toDate())
      .map((d) => `${d.getDate()}/${d.getMonth() + 1}`)
      .join(", ");

    const dropDate = formattedDates.split(", ")[0] || formattedDates;
    const dropTime = after.drop_time || "N/A";

    const accessToken = WHATSAPP_ACCESS_TOKEN.value();
    const phoneNumberId = WHATSAPP_PHONE_NUMBER_ID.value();
    const url = `https://graph.facebook.com/v23.0/${phoneNumberId}/messages`;

    const payload = {
      messaging_product: "whatsapp",
      to: recipientNumber,
      type: "template",
      template: {
        name: "user_boarding_booking_confirmation",
        language: { code: "en_US" },
        components: [
          {
            type: "body",
            parameters: [
              { type: "text", text: customerName },
              { type: "text", text: orderId },
              { type: "text", text: boardingPartner },
              { type: "text", text: formattedDates },
              { type: "text", text: pets },
              { type: "text", text: dropDate },
              { type: "text", text: dropTime },
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

      logger.info(`✅ WhatsApp message sent successfully for booking ${bookingId}`, response.data);

      await docRef.update({
        wa_confirmation_sent: true,
        wa_sent_at: admin.firestore.FieldValue.serverTimestamp(),
        wa_failure_reason: admin.firestore.FieldValue.delete(),
      });
    } catch (error) {
      const errMsg = error.response?.data?.error?.message || error.message;
      logger.error(`❌ WhatsApp message failed for ${bookingId}:`, errMsg);

      await docRef.update({
        wa_confirmation_sent: false,
        wa_confirmation_failed: true,
        wa_failure_reason: errMsg,
      });
    }
  }
);
