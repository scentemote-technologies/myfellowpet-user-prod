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
export const notifyOnUserBookingRequestCancellation = onDocumentCreated(
  {
    document: 'users-sp-boarding/{serviceId}/cancelled_requests/{requestId}',
    secrets: [SMTP_USER, SMTP_PASS, SMTP_HOST, SMTP_PORT],
  },
  async (event) => {
    console.log('=== notifyOnBookingCancellation TRIGGERED ===');

    if (!event.data) {
      console.log('No event data found. Exiting.');
      return null;
    }

    const db = getFirestore();
    const serviceId = event.params.serviceId;
    const cancelledRequest = event.data.data();
    const userName = cancelledRequest.user_name || 'A user';
    const bookingId = cancelledRequest.bookingId;
    const cancellationReason = cancelledRequest.cancellation_reason?.user_cancel_reason || 'No reason specified';

    console.log(`Booking cancellation from ${userName} for service provider: ${serviceId}`);

    // 1. Get the FCM tokens and the shop owner's email in parallel
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
    const pushPayload = {
      data: {
        title: 'Booking Cancelled!',
        body: `${userName} (Booking ID: ${bookingId}) has cancelled their booking Request. Reason: ${cancellationReason}.`,
        action: 'booking_cancelled',
        serviceId: serviceId,
        bookingId: bookingId,
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
      <p>A booking request with ID <strong>${bookingId}</strong> has been cancelled by <strong>${userName}</strong>.</p>      <p><strong>Reason for cancellation:</strong> ${cancellationReason}</p>
      <p>Please check your dashboard for more details.</p>
      <p>Thanks,<br/><strong>MyFellowPet - Support Team</strong></p>
    `);

    // 4. Send push + email in parallel
    const promises = [];

    if (tokens.length > 0) {
      promises.push(admin.messaging().sendEachForMulticast({ tokens, ...pushPayload }));
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
      const response = await Promise.all(promises);
      console.log('Cancellation notification (push + email) sent successfully.');
      return response;
    } catch (err) {
      console.error('Error sending cancellation notification:', err);
      return null;
    }
  },
);