import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import admin from 'firebase-admin';
import { getFirestore } from 'firebase-admin/firestore';

// Initialize Firebase Admin SDK if not already done
if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * Sends notifications based on the 'display' status of a service provider's shop.
 */
export const notifyOnSuspension = onDocumentUpdated(
  'users-sp-boarding/{serviceId}',
  async (event) => {
    console.log('=== notifyOnDisplayStatusChange TRIGGERED ===');

    if (!event.data) {
      console.error('No event data found. Exiting.');
      return null;
    }

    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    const serviceId = event.params.serviceId;

    // Critical Condition: Ignore the initial case where both adminApproved and display change to true at once.
    if (beforeData.adminApproved === false && afterData.adminApproved === true && afterData.display === true) {
      console.log('Initial admin approval and display change detected. No notification sent.');
      return null;
    }

    let notificationTitle = '';
    let notificationBody = '';

    // Condition 1: Check if 'display' has changed from true to false (suspension)
    if (beforeData.display === true && afterData.display === false) {
      console.log(`Display status changed to 'false' for service provider: ${serviceId}.`);
      notificationTitle = 'Account Suspension Approved';
      notificationBody = 'Your account suspension request has been approved by admin and you are no more listed in the user application.';

    // Condition 2: Check if 'display' has changed from false to true (live again)
    } else if (beforeData.display === false && afterData.display === true) {
      console.log(`Display status changed to 'true' for service provider: ${serviceId}.`);
      notificationTitle = 'You Are Live Again!';
      notificationBody = 'You are now live again and users can see your shop and make bookings.';
    } else {
      // No relevant change in the 'display' field
      console.log('No relevant change in display status. Exiting.');
      return null;
    }

    const db = getFirestore();
    // 1. Get the FCM tokens for the service provider
    const tokensSnapshot = await db
      .collection('users-sp-boarding')
      .doc(serviceId)
      .collection('notification_settings')
      .get();

    const tokens = tokensSnapshot.docs
      .map(doc => doc.data().fcm_token)
      .filter(token => !!token);

    if (tokens.length === 0) {
      console.log(`No FCM tokens found for service provider ${serviceId}.`);
      return null;
    }

    // 2. Create the notification payload
    const payload = {
      data: {
        title: notificationTitle,
        body: notificationBody,
        action: 'display_status_change',
        serviceId: serviceId,
      },
    };

    // 3. Send the notification to all tokens
    try {
      const response = await admin.messaging().sendEachForMulticast({ tokens, ...payload });
      console.log('FCM sendEachForMulticast response:', response);
      return response;
    } catch (err) {
      console.error('Error sending FCM notification:', err);
      return null;
    }
  }
);