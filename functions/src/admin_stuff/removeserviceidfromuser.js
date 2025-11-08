import { onCall } from "firebase-functions/v2/https";
import admin from "firebase-admin";

admin.initializeApp();

export const removeServiceIdFromUser = onCall(async (request) => {
  const { uid, serviceId } = request.data;
  if (!uid || !serviceId) {
    return { success: false, error: "UID and serviceId are required" };
  }

  try {
    const user = await admin.auth().getUser(uid);
    const claims = user.customClaims || {};
    let serviceIds = claims.serviceIds || [];

    // Remove the given serviceId
    serviceIds = serviceIds.filter((id) => id !== serviceId);

    // Update custom claims
    await admin.auth().setCustomUserClaims(uid, {
      ...claims,
      serviceIds,
    });

    return { success: true, serviceIds };
  } catch (error) {
    console.error("Error removing serviceId:", error);
    return { success: false, error: error.message };
  }
});
