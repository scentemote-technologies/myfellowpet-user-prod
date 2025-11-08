// Firebase Admin SDK for interacting with Firestore
const admin = require('firebase-admin');
// Axios for making HTTP requests to the WhatsApp Cloud API
const axios = require('axios');
// V2 Firestore trigger function
const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
// DefineSecret for securely accessing environment variables
const { defineSecret } = require('firebase-functions/params');

// Initialize Firebase Admin SDK
admin.initializeApp();

// --- 1. Define Secrets ---
// These parameters reference the secrets you set via the CLI:
// firebase functions:secrets:set WA_TOKEN
// firebase functions:secrets:set WA_PHONE_NUMBER_ID
const WA_TOKEN = defineSecret('WA_TOKEN');
const WA_PHONE_NUMBER_ID = defineSecret('WA_PHONE_NUMBER_ID');

/**
 * Sends a WhatsApp template message when 'sp_confirmation' changes to true.
 * Uses v2 syntax and securely bound secrets.
 */
exports.sendSpConfirmedBookingMessage = onDocumentUpdated({
    // Firestore Path for the booking documents
    document: 'users-sp-boarding/{serviceId}/service_request_boarding/{bookingId}',
    // Set your desired region, e.g., 'asia-south1'
    region: 'asia-south1',
    // BIND the secrets to this specific function
    secrets: [WA_TOKEN, WA_PHONE_NUMBER_ID],
    maxInstances: 2,
}, async (event) => {
    // Exit if no change occurred or event data is missing
    if (!event.data) {
        return;
    }

    const newData = event.data.after.data();
    const oldData = event.data.before.data();
    const docRef = event.data.after.ref;
    const requestId = event.params.bookingId;

    // 2. Access Secret Values at runtime
    const WHATSAPP_TOKEN = WA_TOKEN.value();
    const PHONE_NUMBER_ID = WA_PHONE_NUMBER_ID.value();
    const WA_API_URL = `https://graph.facebook.com/v18.0/${PHONE_NUMBER_ID}/messages`;

    // 3. Check Confirmation and Sent Status
    const spConfirmedNew = newData.sp_confirmation === true;
    const spConfirmedOld = oldData.sp_confirmation === true;
    const messageAlreadySent = newData.wa_confirmation_sent === true;

    // Condition to send the message: new confirmation is true, but it was not true before, and hasn't been sent yet.
    if (!spConfirmedNew || spConfirmedOld || messageAlreadySent) {
        console.log(`Condition not met for ${requestId}. Old state: ${spConfirmedOld}, New state: ${spConfirmedNew}, Sent: ${messageAlreadySent}`);
        return;
    }

    console.log(`SP Confirmation TRUE for booking ${requestId}. Preparing WhatsApp message...`);

    // 4. Extract and Format Template Data
    const recipientNumber = newData.phone_number;
    const userName = newData.user_name || 'Pet Parent';
    const shopName = newData.shopName || 'The Service Provider';

    if (!recipientNumber) {
         console.error(`Recipient phone number missing for ${requestId}. Aborting WA message.`);
         return;
    }

    // Format Dates ({{4}})
    // Map Firestore Timestamps to Date objects for formatting
    const rawDates = (newData.selectedDates || [])
        .map(ts => ts.toDate());

    const formattedDates = rawDates
        // Format as DD/MM (JavaScript months are 0-indexed, so we add 1)
        .map(d => `${d.getDate()}/${d.getMonth() + 1}`)
        .join(', ');

    // Format Pets ({{5}})
    const petNames = (newData.pet_name || []).join(', ');

    // 5. Define Template Parameters (Order is crucial: 1, 2, 3, 4, 5)
    const templateParams = [
        { type: 'text', text: userName },       // {{1}} User Name
        { type: 'text', text: shopName },       // {{2}} Shop Name
        { type: 'text', text: requestId },      // {{3}} Request ID (Doc ID)
        { type: 'text', text: formattedDates }, // {{4}} Dates String
        { type: 'text', text: petNames },       // {{5}} Pets String
    ];

    // 6. Build WhatsApp Message Payload
    const messagePayload = {
        messaging_product: 'whatsapp',
        to: recipientNumber,
        type: 'template',
        template: {
            name: 'sp_confirmed_overnight_boarding_request', // Your approved template name
            language: { code: 'en' },
            components: [
                {
                    type: 'body',
                    parameters: templateParams,
                },
            ],
        },
    };

    // 7. Send the Message via Axios
    try {
        await axios.post(WA_API_URL, messagePayload, {
            headers: {
                'Authorization': `Bearer ${WHATSAPP_TOKEN}`,
                'Content-Type': 'application/json',
            },
        });

        console.log(`WhatsApp message successfully sent for booking ${requestId}`);

        // Record success in Firestore
        await docRef.update({
            wa_confirmation_sent: true,
            wa_sent_at: admin.firestore.FieldValue.serverTimestamp(),
            wa_failure_reason: admin.firestore.FieldValue.delete(),
        });

    } catch (error) {
        // Safe way to extract error message from an axios response
        const errorMsg = error.response?.data?.error?.message || error.message;
        console.error(`Error sending WA message for ${requestId}:`, errorMsg);

        // Record failure in Firestore
        await docRef.update({
            wa_confirmation_sent: false,
            wa_confirmation_failed: true,
            wa_failure_reason: errorMsg,
        });
    }
});