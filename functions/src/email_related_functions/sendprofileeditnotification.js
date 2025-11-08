import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import admin from 'firebase-admin';
import nodemailer from 'nodemailer';
import { defineSecret } from 'firebase-functions/params';

// Initialize Firebase Admin SDK if not already done
if (!admin.apps.length) {
  admin.initializeApp();
}

// Define secrets for secure email credentials
const SMTP_USER = defineSecret('SMTP_USER');
const SMTP_PASS = defineSecret('SMTP_PASS');
const SMTP_HOST = defineSecret('SMTP_HOST');
const SMTP_PORT = defineSecret('SMTP_PORT');

// ** This is your publicly hosted image URL **
const LOGO_URL = 'https://firebasestorage.googleapis.com/v0/b/petproject-test-g.firebasestorage.app/o/company_logos%2Fweb_logo.png?alt=media&token=c3fa3ff4-6fdc-4f41-83f8-754619fa962c';

/**
 * Sends a push notification and an email to a service provider when their profile edit request
 * has been reviewed (approved or rejected).
 */
export const sendProfileEditNotification = onDocumentUpdated(
  {
    document: 'users-sp-boarding/{serviceId}/profile_edit_requests/{editRequestId}',
    secrets: [SMTP_USER, SMTP_PASS, SMTP_HOST, SMTP_PORT],
  },
  async (event) => {
    console.log('=== sendProfileEditNotification TRIGGERED ===');

    if (!event.data.before || !event.data.after) {
      console.log('No data found for document update. Exiting.');
      return null;
    }

    const serviceId = event.params.serviceId;
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();

    // Check if the 'handled' field has changed from false to true
    if (beforeData.handled === false && afterData.handled === true) {
      console.log(`Profile edit request handled for service provider: ${serviceId}`);

      // 1. Determine the notification and email content
      const rejectedFields = afterData.rejectedFields;
      const totalChanges = afterData.changes.length;
      let notificationTitle = '';
      let notificationBody = '';
      let emailSubject = '';
      let emailBody = '';
      const approvedFields = afterData.approvedFields || [];

      // Create a base HTML template with the logo
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

      if (rejectedFields && Object.keys(rejectedFields).length === totalChanges) {
        // Case: ALL fields were rejected
        notificationTitle = 'Profile Edit Request Rejected';
        notificationBody = 'Your profile edit request was reviewed, but all of the requested changes were rejected. Kindly check your dashboard for details.';
        emailSubject = 'Profile Edit Request Rejected';
        emailBody = baseHtml(`
          <p>Hi there,</p>
          <p>Your recent profile edit request has been fully reviewed and <strong>all of the requested changes were rejected</strong>.</p>
          <p>Kindly log in to your dashboard for more details.</p>
          <p>Thanks,<br/><strong>MyFellowPet - Support Team</strong></p>
        `);
      } else if (rejectedFields && Object.keys(rejectedFields).length > 0) {
        // Case: SOME fields were rejected
        const rejectedFieldNames = Object.keys(rejectedFields).join(', ');
        notificationTitle = 'Profile Edit Request Reviewed';
        notificationBody = `Your profile edit request was reviewed. Some fields were rejected: ${rejectedFieldNames}. Kindly check your dashboard for details.`;
        emailSubject = 'Your profile edit request has been reviewed';
        emailBody = baseHtml(`
          <p>Hi there,</p>
          <p>Your recent profile edit request was reviewed. The following fields were rejected:</p>
          <ul>
            ${Object.entries(afterData.rejectedFields).map(([k, v]) => `<li><strong>${k}</strong> (Reason: ${v})</li>`).join('')}
          </ul>
          <p>The following fields were approved:</p>
          <ul>
            ${approvedFields.map(field => `<li><strong>${field}</strong></li>`).join('')}
          </ul>
          <p>Kindly log in to your dashboard for more details.</p>
          <p>Thanks,<br/><strong>MyFellowPet - Support Team</strong></p>
        `);
      } else {
        // Case: All fields were approved
        notificationTitle = 'Profile Edit Request Approved! 🎉';
        notificationBody = 'Your profile edit request has been approved and your changes are now live.';
        emailSubject = 'Profile Edit Request Approved! 🎉';
        emailBody = baseHtml(`
          <p>Hi there,</p>
          <p>Your recent profile edit request has been <strong>approved</strong> and your changes are now live!</p>
          <p>The following fields were updated:</p>
          <ul>
            ${approvedFields.map(field => `<li><strong>${field}</strong></li>`).join('')}
          </ul>
          <p>Thanks,<br/><strong>MyFellowPet - Support Team</strong></p>
        `);
      }

      // 2. Fetch the recipient email and FCM tokens
      const serviceDoc = await admin.firestore().doc(`users-sp-boarding/${serviceId}`).get();
      const ownerEmail = serviceDoc.data()?.owner_email;

      if (!ownerEmail) {
        console.error(`Service ${serviceId} has no owner_email field. Cannot send email.`);
      }

      const tokensSnapshot = await admin.firestore()
        .collection('users-sp-boarding')
        .doc(serviceId)
        .collection('notification_settings')
        .get();

      const tokens = tokensSnapshot.docs
        .map(doc => doc.data().fcm_token)
        .filter(token => !!token);

      // 3. Send both Push Notification and Email
      const promises = [];

      // Send Push Notification
      if (tokens.length > 0) {
        const payload = {
          data: {
            title: notificationTitle,
            body: notificationBody,
            action: 'profile_edit_reviewed',
            serviceId: serviceId,
          },
        };
        promises.push(admin.messaging().sendEachForMulticast({ tokens, ...payload }));
      } else {
        console.log('No FCM tokens found for the service provider.');
      }

      // Send Email
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
        console.log('Notifications and emails sent successfully.');
        return null;
      } catch (err) {
        console.error('Error in sending notifications:', err);
        return null;
      }
    } else {
      console.log('No relevant change in handled field. Exiting.');
      return null;
    }
  }
);