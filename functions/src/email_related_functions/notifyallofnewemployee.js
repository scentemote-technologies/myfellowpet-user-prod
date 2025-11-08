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
 * Sends a notification to all employees and the owner when a new employee is added.
 */
export const notifyAllOfNewEmployee = onDocumentCreated(
  {
    document: 'users-sp-boarding/{serviceId}/employees/{employeeId}',
    secrets: [SMTP_USER, SMTP_PASS, SMTP_HOST, SMTP_PORT],
  },
  async (event) => {
    console.log('=== notifyAllOfNewEmployee TRIGGERED ===');

    if (!event.data) {
      console.log('No event data found. Exiting.');
      return null;
    }

    const db = getFirestore();
    const serviceId = event.params.serviceId;
    const newEmployee = event.data.data();
    const newEmployeeId = event.params.employeeId;
    const employeeName = newEmployee.name || 'A new employee';
    const employeeRole = newEmployee.role || 'Unspecified Role';

    // 1. Fetch push notification tokens AND the shop owner's email
    const [tokensSnapshot, shopDoc] = await Promise.all([
      db.collection('users-sp-boarding').doc(serviceId).collection('notification_settings').get(),
      db.collection('users-sp-boarding').doc(serviceId).get(),
    ]);

    const tokens = tokensSnapshot.docs
      .map(doc => doc.data().fcm_token)
      .filter(token => !!token);

    const ownerEmail = shopDoc.data()?.owner_email;

    // 2. Create the push notification payload
    const pushPayload = {
      data: {
        title: 'New Employee Added!',
        body: `${employeeName} has been added as a ${employeeRole}. Check your dashboard for more details.`,
        action: 'new_employee_added',
        serviceId: serviceId,
        newEmployeeId: newEmployeeId,
      },
    };

    // 3. Create the email payload
    const logoHtml = `<img src="${LOGO_URL}" alt="Logo" style="width:120px;height:auto;display:block;margin-bottom:20px;">`;
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

    const emailSubject = '🔔 New Employee Added!';
    const emailBody = baseHtml(`
      <p>Hi there,</p>
      <p>A new employee, <strong>${employeeName}</strong>, has been added to your team with the <strong>role: ${employeeRole}</strong>.</p>
      <p>Please log in to your dashboard to manage your employee list.</p>
      <p>Thanks,<br/>MyFellowPet - Support Team</p>
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
        from: `"PetProject Notifications" <${SMTP_USER.value()}>`,
        to: ownerEmail,
        subject: emailSubject,
        html: emailBody,
      };

      promises.push(transporter.sendMail(mailOptions));
    }

    try {
      await Promise.all(promises);
      console.log('Notification (push + email) sent successfully.');
      return null;
    } catch (err) {
      console.error('Error sending notification:', err);
      return null;
    }
  }
);