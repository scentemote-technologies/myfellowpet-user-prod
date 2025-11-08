import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import admin from 'firebase-admin';

// Initialize Firebase Admin SDK if not already done
if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * Sends a notification to the recipient of a new chat message.
 * This function is triggered when a new message document is created in the 'messages' subcollection.
 */
export const sendChatNotification = onDocumentCreated(
  'chats/{chatId}/messages/{messageId}',
  async (event) => {
    console.log('=== sendChatNotification TRIGGERED ===');
    const db = admin.firestore();

    if (!event.data) {
      console.error('No event.data found - document might be empty.');
      return null;
    }
    const newMessage = event.data.data();
    const chatRef = event.data.ref.parent.parent;
    const chatId = chatRef.id;

    console.log('New message data:', newMessage);
    console.log('Chat ID:', chatId);

    // We only want to send notifications for messages sent by the user to the service provider.
    if (newMessage.sent_by !== 'user') {
      console.log('Message was not sent by a user. Skipping notification.');
      return null;
    }

    try {
      // 🔹 Check the last message sender (skip if SP was last)
      const prevMessages = await chatRef.collection('messages')
        .orderBy('timestamp', 'desc')
        .limit(2)
        .get();

      if (prevMessages.size > 1) {
        const [firstDoc, secondDoc] = prevMessages.docs;
        const prevMessage = firstDoc.id === event.params.messageId
          ? secondDoc.data()
          : firstDoc.data();

        if (prevMessage.sent_by === 'sp') {
          console.log('Last message was from service provider. Skipping notification.');
          return null;
        }
      }

      // Get the chat document to check lastReadBy status
      const chatDoc = await chatRef.get();
      if (!chatDoc.exists) {
        console.error(`Chat document ${chatId} does not exist.`);
        return null;
      }

      const chatData = chatDoc.data();
      const serviceId = chatId.split('_')[0]; // Extract serviceId from the document ID
      const bookingId = chatId.split('_')[1]; // Extract the bookingId from the document ID

      // Check if the SP has already read this message or a later one.
      const lastReadBySp = chatData[`lastReadBy_${serviceId}`];

      if (lastReadBySp && lastReadBySp.toDate() >= newMessage.timestamp.toDate()) {
        console.log('Service provider has already read this message or a newer one. Skipping notification.');
        return null;
      }

      // Check for an existing unread notification to prevent spamming
      const notificationsSentRef = chatRef.collection('notifications_sent');
      const latestNotification = await notificationsSentRef
        .orderBy('timestamp', 'desc')
        .limit(1)
        .get();

      if (!latestNotification.empty) {
          const lastSentTimestamp = latestNotification.docs[0].data().timestamp;
          if (lastSentTimestamp.toDate() > (lastReadBySp ? lastReadBySp.toDate() : new Date(0))) {
              console.log('A notification has already been sent for this unread state. Skipping new notification.');
              return null;
          }
      }

      // 1. Get the FCM tokens for the service provider
      const tokensSnapshot = await db
        .collection('users-sp-boarding')
        .doc(serviceId)
        .collection('notification_settings')
        .get();

      const tokens = tokensSnapshot.docs.map(doc => doc.data().fcm_token).filter(token => !!token);

      if (tokens.length === 0) {
        console.log('No FCM tokens found for service provider.');
        return null;
      }

      // Fetch booking details from the proper location
      const bookingDoc = await db.collection('users-sp-boarding').doc(serviceId)
        .collection('service_request_boarding').doc(bookingId).get();

      const userName = bookingDoc.exists && bookingDoc.data().user_name ? bookingDoc.data().user_name : 'A user';
      const fetchedBookingId = bookingDoc.exists && bookingDoc.data().bookingId ? bookingDoc.data().bookingId : 'N/A';

      // 2. Create the message payload with the new body
      const payload = {
        data: {
          title: `New Message from ${userName}!`,
          body: `${userName} (booking ID: ${fetchedBookingId}) wants to talk to you! Kindly open their chat.`,
          chatId: chatId,
          serviceId: serviceId,
          // Add a type for the client app to handle the notification
          type: 'new_chat_message',
        }
      };

      // 3. Send the notification to all tokens
      const response = await admin.messaging().sendEachForMulticast({ tokens, ...payload });
      console.log('FCM sendEachForMulticast response:', response);

      // 4. Record that a notification has been sent for this message.
      await notificationsSentRef.add({
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        messageId: event.params.messageId,
      });

      return response;

    } catch (err) {
      console.error('Error sending chat notification:', err);
      return null;
    }
  }
);
