import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { defineSecret } from 'firebase-functions/params';
import admin from 'firebase-admin';
import { getFirestore } from 'firebase-admin/firestore';
import nodemailer from 'nodemailer';

// Re-use the existing admin app initialization
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
 * Sends a notification when a service provider's profile is approved by an admin.
 * Listens for changes to the 'adminApproved' field in any user-sp-boarding document.
 */
export const sendApprovalNotification = onDocumentUpdated(
  {
    document: 'users-sp-boarding/{serviceId}',
    secrets: [SMTP_USER, SMTP_PASS, SMTP_HOST, SMTP_PORT],
  },
  async (event) => {
    console.log('=== sendApprovalNotification TRIGGERED ===');

    // Check for document existence
    if (!event.data.before || !event.data.after) {
      console.log('No data found for document update. Exiting.');
      return null;
    }

    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    const serviceId = event.params.serviceId;

    // Check if the 'adminApproved' field has changed from false to true
    if (beforeData.adminApproved === false && afterData.adminApproved === true) {
      console.log(`Approval detected for service provider: ${serviceId}`);

      const db = getFirestore();

      // 1. Fetch the FCM tokens AND the shop owner's email in parallel
      const [tokensSnapshot, shopDoc] = await Promise.all([
        db.collection('users-sp-boarding').doc(serviceId).collection('notification_settings').get(),
        db.collection('users-sp-boarding').doc(serviceId).get(),
      ]);

      const tokens = tokensSnapshot.docs
        .map(doc => doc.data().fcm_token)
        .filter(token => !!token);

      const ownerEmail = shopDoc.data()?.owner_email;

      const shopName = afterData.shop_name || 'Your Business';

      // 2. Create the push notification payload
      const pushPayload = {
        data: {
          title: 'Congratulations! Your Profile is Live! 🎉',
          body: `Your application for ${shopName} has been approved. You are now listed on the user application!`,
          action: 'admin_approved',
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

      const emailSubject = '✅ Your Profile Has Been Approved!';
      const emailBody = baseHtml(`
        <p>Hi,</p>
        <p>We are excited to let you know that your application for <strong>${shopName}</strong> has been reviewed and approved!</p>
        <p>Your business profile is now live and listed on the application for customers to find.</p>
        <p>You can now start receiving booking requests and managing your services.</p>
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
        console.log('Approval notification (push + email) sent successfully.');
        return response;
      } catch (err) {
        console.error('Error sending approval notification:', err);
        return null;
      }

    } else {
      console.log('No relevant change in `adminApproved` field. Exiting.');
      return null;
    }
  },
);