import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
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
 * Sends a notification when a pending booking request is confirmed.
 */
export const sendBookingConfirmationNotification = onDocumentUpdated(
  {
    document: 'users-sp-boarding/{serviceId}/service_request_boarding/{bookingId}',
    secrets: [SMTP_USER, SMTP_PASS, SMTP_HOST, SMTP_PORT],
  },
  async (event) => {
    console.log('=== sendBookingConfirmationNotification TRIGGERED ===');

    if (!event.data) {
      console.error('No event.data found — document might be empty.');
      return null;
    }

    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();

    // Check if the order_status has just become "confirmed"
    if (beforeData.order_status !== 'confirmed' && afterData.order_status === 'confirmed') {
      const db = getFirestore();
      const serviceId = event.params.serviceId;
      const bookingId = event.params.bookingId;
      const newBooking = afterData;

      console.log(`Booking ID ${bookingId} has been confirmed. Notifying service provider.`);

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

      // Format the booking dates into a readable string
      const selectedDates = newBooking.selectedDates.map(date => {
        const dateObj = date.toDate();
        return dateObj.toLocaleDateString('en-US', { month: 'long', day: 'numeric' });
      }).join(', ');

      // 2. Create the push notification payload
      const pushPayload = {
        data: {
          title: 'Booking Confirmed!',
          body: `You have a new booking confirmation from ${newBooking.user_name} (Booking ID: ${bookingId}) for the following dates: ${selectedDates}.`,
          action: 'booking_confirmed',
          bookingId: bookingId,
          userName: newBooking.user_name,
          userId: newBooking.user_id,
          serviceId: serviceId,
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

      const emailSubject = '✅ Booking Confirmed!';
      const emailBody = baseHtml(`
        <p>Hi,</p>
        <p>A new booking request has been confirmed by <strong>${newBooking.user_name}</strong>.</p>
        <p><strong>Booking ID:</strong> ${bookingId}</p>
        <p><strong>Confirmed Dates:</strong> ${selectedDates}</p>
        <p>Please log in to your dashboard to view the details.</p>
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
        await Promise.all(promises);
        console.log('Booking confirmation (push + email) sent successfully.');
        return null;
      } catch (err) {
        console.error('Error sending booking confirmation notification:', err);
        return null;
      }
    } else {
      console.log('`order_status` was not just confirmed. Exiting.');
      return null;
    }
  },
);