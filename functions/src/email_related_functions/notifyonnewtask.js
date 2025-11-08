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
 * Sends push + email when a new task is assigned to an employee.
 */
export const notifyOnNewTask = onDocumentCreated(
  {
    document: 'users-sp-boarding/{serviceId}/employees/{assignedToId}/tasks/{taskId}',
    secrets: [SMTP_USER, SMTP_PASS, SMTP_HOST, SMTP_PORT],
  },
  async (event) => {
    console.log('=== notifyOnNewTask TRIGGERED ===');

    if (!event.data) {
      console.error('No event.data found — document might be empty.');
      return null;
    }

    const db = getFirestore();
    const serviceId = event.params.serviceId;
    const assignedToId = event.params.assignedToId;
    const newTask = event.data.data();
    const createdById = newTask.createdBy;

    console.log(`New task created for employee: ${assignedToId} in service: ${serviceId}`);

    // 1. Fetch employee + creator details
    const [assignedToSnap, createdBySnap] = await Promise.all([
      db.collection('users-sp-boarding').doc(serviceId).collection('employees').doc(assignedToId).get(),
      db.collection('users-sp-boarding').doc(serviceId).collection('employees').doc(createdById).get(),
    ]);

    const assignedToData = assignedToSnap.exists ? assignedToSnap.data() : {};
    const createdByData = createdBySnap.exists ? createdBySnap.data() : {};

    const assignedToName = assignedToData.name || 'Employee';
    const assignedToEmail = assignedToData.email || null;
    const createdByName = createdByData.name || 'Someone';

    // 2. Push notification tokens
    const tokensSnapshot = await db
      .collection('users-sp-boarding')
      .doc(serviceId)
      .collection('notification_settings')
      .where('employeeId', '==', assignedToId)
      .get();

    const tokens = tokensSnapshot.docs
      .map((doc) => doc.data().fcm_token)
      .filter((token) => !!token);

    // 3. Push Notification Payload
    const notificationTitle = 'New Task Assigned!';
    const notificationBody = `${createdByName} has assigned you a new task.`;

    const payload = {
      data: {
        title: notificationTitle,
        body: notificationBody,
        action: 'new_task_assigned',
        serviceId,
        assignedToId,
      },
    };

    // 4. Email Template
    const logoHtml = `<img src="${LOGO_URL}" alt="Logo" style="width:120px;height:auto;display:block;margin-bottom:20px;">`;

    // FIX: Removed TypeScript annotation here
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


    const emailSubject = '📌 New Task Assigned!';
    const emailBody = baseHtml(`
      <p>Hi ${assignedToName},</p>
      <p><strong>${createdByName}</strong> has assigned you a new task.</p>
      <p><strong>Task Title:</strong> ${newTask.title || 'Untitled Task'}</p>
      <p><strong>Description:</strong> ${newTask.description || 'No description provided'}</p>
      <p>Please log in to your dashboard to view and complete this task.</p>
      <p>Thanks,<br/><strong>MyFellowPet - Support Team</strong></p>
    `);

    // 5. Send push + email in parallel
    const promises = []; // FIX: Removed TypeScript annotation here

    if (tokens.length > 0) {
      promises.push(admin.messaging().sendEachForMulticast({ tokens, ...payload }));
    }

    if (assignedToEmail) {
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
        to: assignedToEmail,
        subject: emailSubject,
        html: emailBody,
      };

      promises.push(transporter.sendMail(mailOptions));
    }

    try {
      await Promise.all(promises);
      console.log('Task notification (push + email) sent successfully.');
      return null;
    } catch (err) {
      console.error('Error sending task notification:', err);
      return null;
    }
  }
);