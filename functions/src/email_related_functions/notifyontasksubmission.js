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
 * Sends a notification to the task creator when a task is submitted.
 */
export const notifyOnTaskSubmission = onDocumentCreated(
  {
    document: 'users-sp-boarding/{serviceId}/employees/{assignedToId}/tasks/{taskId}/task_history/{historyId}',
    secrets: [SMTP_USER, SMTP_PASS, SMTP_HOST, SMTP_PORT],
  },
  async (event) => {
    console.log('=== notifyOnTaskSubmission TRIGGERED ===');

    if (!event.data) {
      console.log('No event data found. Exiting.');
      return null;
    }

    const db = getFirestore();
    const serviceId = event.params.serviceId;
    const assignedToId = event.params.assignedToId;
    const taskId = event.params.taskId;
    const taskHistoryData = event.data.data();

    // Fetch the parent task document to get the creator's ID and task title
    const taskDocRef = db.collection('users-sp-boarding').doc(serviceId).collection('employees').doc(assignedToId).collection('tasks').doc(taskId);
    const taskSnap = await taskDocRef.get();

    if (!taskSnap.exists) {
      console.error(`Task document ${taskId} not found. Exiting.`);
      return null;
    }

    const taskData = taskSnap.data();
    const createdById = taskData.createdBy;

    // Fetch the names and email of the assigned employee and the creator
    const [assignedToSnap, createdBySnap] = await Promise.all([
      db.collection('users-sp-boarding').doc(serviceId).collection('employees').doc(assignedToId).get(),
      db.collection('users-sp-boarding').doc(serviceId).collection('employees').doc(createdById).get(),
    ]);

    const assignedToName = assignedToSnap.exists ? assignedToSnap.data().name : 'An employee';
    const createdByData = createdBySnap.exists ? createdBySnap.data() : {};
    const createdByName = createdByData.name || 'Someone';
    const createdByEmail = createdByData.email || null;

    // Format the submission date
    const submittedDate = taskHistoryData.submittedAt.toDate().toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric'
    });

    // 1. Get the FCM tokens for the creator of the task
    const tokensSnapshot = await db
      .collection('users-sp-boarding')
      .doc(serviceId)
      .collection('notification_settings')
      .where('employeeId', '==', createdById)
      .get();

    const tokens = tokensSnapshot.docs
      .map(doc => doc.data().fcm_token)
      .filter(token => !!token);

    if (tokens.length === 0 && !createdByEmail) {
      console.log(`No notification method found for the task creator with ID: ${createdById}. Exiting.`);
      return null;
    }
    console.log(`Found ${tokens.length} tokens and email: ${createdByEmail ? 'yes' : 'no'} for task creator ${createdById}.`);

    // 2. Create the notification payload
    const pushPayload = {
      data: {
        title: 'Task Submitted! 🎉',
        body: `${assignedToName} has submitted the task: "${taskData.title}" on ${submittedDate}.`,
        action: 'task_submitted',
        serviceId: serviceId,
        assignedToId: assignedToId,
        taskId: taskId,
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

    const emailSubject = '✅ Task Submitted!';
    const emailBody = baseHtml(`
      <p>Hi ${createdByName},</p>
      <p>The task <strong>"${taskData.title}"</strong> has been submitted by ${assignedToName}.</p>
      <p>You can review the submitted work in your dashboard.</p>
      <p>Thanks,<br/><strong>MyFellowPet - Support Team</strong></p>
    `);

    // 4. Send push + email in parallel
    const promises = [];

    if (tokens.length > 0) {
      promises.push(admin.messaging().sendEachForMulticast({ tokens, ...pushPayload }));
    }

    if (createdByEmail) {
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
        to: createdByEmail,
        subject: emailSubject,
        html: emailBody,
      };

      promises.push(transporter.sendMail(mailOptions));
    }

    try {
      const response = await Promise.all(promises);
      console.log('Task submission notification (push + email) sent successfully.');
      return response;
    } catch (err) {
      console.error('Error sending task submission notification:', err);
      return null;
    }
  },
);