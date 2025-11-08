import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { defineSecret } from 'firebase-functions/params';
import admin from 'firebase-admin';
import nodemailer from 'nodemailer';

// Initialize Firebase Admin SDK if not already done
if (!admin.apps.length) {
  admin.initializeApp();
}

// ✅ Define secrets for secure email credentials
const SMTP_USER = defineSecret('SMTP_USER');
const SMTP_PASS = defineSecret('SMTP_PASS');
const SMTP_HOST = defineSecret('SMTP_HOST');
const SMTP_PORT = defineSecret('SMTP_PORT');

// Logo for email template
const LOGO_URL =
  'https://firebasestorage.googleapis.com/v0/b/petproject-test-g.firebasestorage.app/o/company_logos%2Fweb_logo.png?alt=media&token=c3fa3ff4-6fdc-4f41-83f8-754619fa962c';

/**
 * Sends both push notification + email when a new booking request is created.
 */
export const sendBookingRequestNotification = onDocumentCreated(
  {
    document: 'users-sp-boarding/{serviceId}/service_request_boarding/{bookingId}',
    secrets: [SMTP_USER, SMTP_PASS, SMTP_HOST, SMTP_PORT],
  },
  async (event) => {
    console.log('=== sendBookingNotification TRIGGERED ===');

    if (!event.data) {
      console.error('No event.data found — document might be empty.');
      return null;
    }

    const newBooking = event.data.data();
    const serviceId = event.params.serviceId;

    console.log('New booking data:', newBooking);

    // 1. Get FCM tokens for the service provider
    const tokensSnapshot = await admin
      .firestore()
      .collection('users-sp-boarding')
      .doc(serviceId)
      .collection('notification_settings')
      .get();

    const tokens = tokensSnapshot.docs
      .map((doc) => {
        const token = doc.data().fcm_token;
        console.log(`➡️ Token found: ${token}`);
        return token;
      })
      .filter((token) => !!token);

      if (tokens.length === 0) {
      console.warn(`⚠️ No valid FCM tokens found for serviceId: ${serviceId}`);
      } else {
        console.log(`✅ Found ${tokens.length} FCM tokens`);
      }

    // 2. Format booking dates
    const selectedDates = newBooking.selectedDates
      .map((date) => {
        const dateObj = date.toDate();
        return dateObj.toLocaleDateString('en-US', {
          month: 'long',
          day: 'numeric',
        });
      })
      .join(', ');

    // 3. Push Notification Payload
    const notificationTitle = 'New Booking Request!';
    const notificationBody = `You have a new booking request from ${newBooking.user_name} (${newBooking.user_id}) on: ${selectedDates}.`;

    const payload = {
      data: {
        title: notificationTitle,
        body: notificationBody,
        bookingId: newBooking.bookingId,
        userName: newBooking.user_name,
        userId: newBooking.user_id,
        selectedDates: selectedDates,
        serviceId: serviceId,

      },
    };

    console.log('📤 Push payload prepared:', payload);


    // 4. Email Payload
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

    const emailSubject = '📩 New Booking Request!';
    const emailBody = baseHtml(`
      <p>Hi there,</p>
      <p>You’ve received a new booking request.</p>
      <p><strong>From:</strong> ${newBooking.user_name} (${newBooking.user_id})</p>
      <p><strong>Requested Dates:</strong> ${selectedDates}</p>
      <p>Please log in to your dashboard to view and respond to this request.</p>
      <p>Thanks,<br/><strong>MyFellowPet - Support Team</strong></p>
    `);

    // 5. Get owner email
    const serviceDoc = await admin
      .firestore()
      .doc(`users-sp-boarding/${serviceId}`)
      .get();
    const ownerEmail = serviceDoc.data()?.owner_email;

    // 6. Send push + email in parallel
    const promises = [];

    // Push
    if (tokens.length > 0) {
      promises.push(
        admin
          .messaging()
          .sendEachForMulticast({ tokens, ...payload })
          .then((response) => {
            console.log(`🚀 Push notification sent: ${response.successCount} success / ${response.failureCount} failed`);
            if (response.responses) {
              response.responses.forEach((r, idx) => {
                if (!r.success) {
                  console.warn(`❌ Token [${tokens[idx]}] failed:`, r.error);
                }
              });
            }
          })
          .catch((err) => {
            console.error('❌ Push notification error:', err);
          })
      );
    }

    // Email
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
      console.log('Booking notification (push + email) sent successfully.');
      return null;
    } catch (err) {
      console.error('Error sending booking notification:', err);
      return null;
    }
  }
);
