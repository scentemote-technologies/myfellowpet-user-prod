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
 * Sends a notification to the service provider and owner when a user cancels a booking.
 */
export const notifySpOnUserCancellation = onDocumentCreated(
  {
    document: 'users-sp-boarding/{serviceId}/cancellations/{historyType}/{cancellationDocId}',
    secrets: [SMTP_USER, SMTP_PASS, SMTP_HOST, SMTP_PORT],
  },
  async (event) => {
    console.log('=== notifySpOnUserCancellation TRIGGERED ===');

    if (!event.data) {
      console.log('No event data found. Exiting.');
      return null;
    }

    const { serviceId, historyType } = event.params;

    // Only continue if it's user_cancellation_history
    if (historyType !== 'user_cancellation_history') {
      console.log(`Skipping because historyType = ${historyType}`);
      return null;
    }

    const db = getFirestore();
    const cancellationData = event.data.data();
    const bookingId = cancellationData.bookingId;
    const userName = cancellationData.user_name || 'A user';
    const cancellationDetails = cancellationData.cancellation_details;

    let cancelledDates = [];
    if (cancellationDetails) {
      cancelledDates = Object.keys(cancellationDetails).map(date => {
        const d = new Date(date);
        return d.toLocaleDateString('en-US', {
          weekday: 'long',
          year: 'numeric',
          month: 'long',
          day: 'numeric',
        });
      });
    }

    console.log(`User ${userName} cancelled booking ${bookingId} for service ${serviceId}`);

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
        title: 'Booking Cancelled',
        body: `${userName} (Booking ID: ${bookingId}) cancelled for dates: ${cancelledDates.join(', ')}`,
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

    const emailSubject = '🚫 Booking Cancelled!';
    const emailBody = baseHtml(`
      <p>Hi,</p>
      <p>A booking with ID <strong>${bookingId}</strong> has been cancelled by <strong>${userName}</strong>.</p>
      <p><strong>Cancelled Dates:</strong> ${cancelledDates.join(', ')}</p>
      <p>Please check your dashboard for more details.</p>
      <p>Thanks,<br/><strong>MyFellowPet - Support Team</strong></p>
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
      console.log('Cancellation notification (push + email) sent successfully.');
      return null;
    } catch (err) {
      console.error('Error sending cancellation notification:', err);
      return null;
    }
  },
);