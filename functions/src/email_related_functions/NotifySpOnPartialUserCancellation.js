import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { defineSecret } from 'firebase-functions/params';
import admin from 'firebase-admin';
import { getFirestore } from 'firebase-admin/firestore';
import nodemailer from 'nodemailer';

// Initialize Firebase Admin SDK if not already done
if (!admin.apps.length) {
  admin.initializeApp();
}

// Define secrets for secure email credentials
const SMTP_USER = defineSecret('SMTP_USER');
const SMTP_PASS = defineSecret('SMTP_PASS');
const SMTP_HOST = defineSecret('SMTP_HOST');
const SMTP_PORT = defineSecret('SMTP_PORT');

// Logo for email template
const LOGO_URL =
  'https://firebasestorage.googleapis.com/v0/b/petproject-test-g.firebasestorage.app/o/company_logos%2Fweb_logo.png?alt=media&token=c3fa3ff4-6fdc-4f41-83f8-754619fa962c';

/**
 * Sends a notification to the service provider when a user cancels (partial or full) a booking.
 */
export const notifySpOnPartialUserCancellation = onDocumentCreated(
  {
    document: 'users-sp-boarding/{userId}/service_request_boarding/{bookingId}/{historyType}/{cancellationDocId}',
    secrets: [SMTP_USER, SMTP_PASS, SMTP_HOST, SMTP_PORT],
  },
  async (event) => {
    console.log('=== notifySpOnBookingCancellation TRIGGERED ===');

    if (!event.data) {
      console.log('No event data found. Exiting.');
      return null;
    }

    const db = getFirestore();
    const cancellationData = event.data.data();
    const { userId, bookingId, historyType } = event.params;

    // 🚨 Only handle if it's user_cancellation_history (skip sp_cancellation_history)
    if (historyType !== 'user_cancellation_history') {
      console.log(`Skipping because historyType = ${historyType}`);
      return null;
    }

    // Get the booking data to find the service provider's ID and user's name
    const bookingSnapshot = await db
      .collection('users-sp-boarding')
      .doc(userId)
      .collection('service_request_boarding')
      .doc(bookingId)
      .get();

    const bookingData = bookingSnapshot.data();

    if (!bookingData) {
      console.log(`Booking data not found for bookingId: ${bookingId}.`);
      return null;
    }

    const { service_id: serviceId, user_name: userName } = bookingData;
    const { cancellation_details: cancellationDetails } = cancellationData;

    let cancelledDates = [];
    if (cancellationDetails) {
      cancelledDates = Object.keys(cancellationDetails).map(date => {
        const d = new Date(date);
        return d.toLocaleDateString('en-US', {
          weekday: 'long',
          year: 'numeric',
          month: 'long',
          day: 'numeric'
        });
      });
    }

    console.log(`User ${userName} cancelled booking ${bookingId} for service provider: ${serviceId}`);

    // 1. Get FCM tokens AND owner email in parallel
    const [tokensSnapshot, shopDoc] = await Promise.all([
      db.collection('users-sp-boarding')
        .doc(serviceId)
        .collection('notification_settings')
        .get(),
      db.collection('users-sp-boarding').doc(serviceId).get(),
    ]);

    const tokens = tokensSnapshot.docs
      .map(doc => doc.data().fcm_token)
      .filter(token => !!token);

    const ownerEmail = shopDoc.data()?.owner_email;

    // 2. Create the push notification payload
    const pushMessage = {
      tokens,
      notification: {
        title: 'Booking Partially Cancelled',
        body: `${userName} (Booking ID: ${bookingId}) has cancelled for the following dates: ${cancelledDates.join(', ')}.`,
      },
    };

    // 3. Create the email payload
    const logoHtml = `<img src="${LOGO_URL}" alt="MyFellowPet Logo" style="width:100px;height:auto;display:block;margin-bottom:20px;">`;
    const baseHtml = (content) => `
      <body style="font-family:Arial,sans-serif;font-size:16px;line-height:1.6;color:#333;padding:20px;">
        <div style="max-width:600px;margin:auto;border:1px solid #ddd;border-radius:8px;padding:20px;">
          <div style="text-align:center;">
            ${logoHtml}
          </div>
          ${content}
        </div>
      </body>
    `;

    const emailSubject = '🚫 Booking Partially Cancelled';
    const emailBody = baseHtml(`
      <p>Hi,</p>
      <p>A booking with ID <strong>${bookingId}</strong> has been partially cancelled by <strong>${userName}</strong>.</p>
      <p>The following dates have been cancelled: ${cancelledDates.join(', ')}</p>
      <p>Please check your dashboard for more details.</p>
      <p>Thanks,<br/>MyFellowPet Team</p>
    `);

    // 4. Send push + email in parallel
    const promises = [];

    if (tokens.length > 0) {
      promises.push(admin.messaging().sendEachForMulticast(pushMessage));
    }

    if (ownerEmail) {
      const transporter = nodemailer.createTransport({
        host: SMTP_HOST.value(),
        port: parseInt(SMTP_PORT.value()),
        secure: true,
        auth: {
          user: SMTP_USER.value(),
          pass: SMTP_PASS.value(),
        },
      });

      const mailOptions = {
        from: `"MyFellowPet Notifications" <${SMTP_USER.value()}>`,
        to: ownerEmail,
        subject: emailSubject,
        html: emailBody,
      };

      promises.push(transporter.sendMail(mailOptions));
    }

    try {
      await Promise.all(promises);
      console.log('Partial cancellation notification (push + email) sent successfully.');
      return null;
    } catch (err) {
      console.error('Error sending partial cancellation notification:', err);
      return null;
    }
  },
);