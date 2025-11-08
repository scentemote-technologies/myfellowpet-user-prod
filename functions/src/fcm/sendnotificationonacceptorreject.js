const {onDocumentUpdated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
admin.initializeApp();

exports.sendNotificationOnAcceptOrReject = onDocumentUpdated(
    "users-sp-boarding/{serviceId}/service_request_boarding/{requestId}",
    async (event) => {
      const beforeData = event.data.before.data();
      const afterData = event.data.after.data();

      const userId = afterData.user_id;
      if (!userId) {
        console.log("No user_id found");
        return;
      }

      try {
        const userDoc = await admin
            .firestore()
            .collection("users")
            .doc(userId)
            .get();
        if (!userDoc.exists) {
          console.log("User doc not found:", userId);
          return;
        }
        const userData = userDoc.data();
        const fcmToken = userData.fcmToken;
        if (!fcmToken) {
          console.log("No FCM token for user:", userId);
          return;
        }

        // If status changed to Confirmed, send acceptance notification
        if (
          beforeData.status !== "Confirmed" &&
          afterData.status === "Confirmed"
        ) {
          const petNames = afterData.pet_name ?
              afterData.pet_name.toString() :
              "your pet(s)";
          const selectedDates = afterData.selectedDates ?
              afterData.selectedDates
                  .map((date) =>
                    date.toDate ?
                      date.toDate().toLocaleDateString() :
                      date,
                  )
                  .join(", ") :
              "N/A";
          const openTime = afterData.openTime || "opening time";
          const closeTime = afterData.closeTime || "closing time";

          const messageBody =
            `Service provider has accepted your booking.` +
            `Kindly make sure to come on ${selectedDates}` +
            `between ${openTime} and ${closeTime} ` +
            `with your ${petNames}.`;

          const message = {
            token: fcmToken,
            notification: {
              title: "Request Accepted",
              body: messageBody,
            },
          };

          const response = await admin.messaging().send(message);
          console.log("Successfully sent acceptance message:", response);
        }

        if (
          (afterData.status === "sp_cancellation" ||
              afterData.status === "user_cancellation") &&
             beforeData.status !== afterData.status
        ) {
          const rejectionReason =
              afterData.rejectionReason ||
              "an unspecified reason";
          const messageBody =
            `Service provider has canceled your booking ` +
            `because of ${rejectionReason}. ` +
            `Tap to know more ` +
            `to see details.`;

          const message = {
            token: fcmToken,
            notification: {
              title: "Request Canceled",
              body: messageBody,
            },
          };

          const response = await admin.messaging().send(message);
          console.log("Successfully sent cancellation message:", response);
        }
      } catch (error) {
        console.error("Error processing notification:", error);
      }
    },
);
