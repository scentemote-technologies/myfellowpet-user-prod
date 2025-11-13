const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

/**
 * ✅ Helper: Format date as YYYY-MM-DD
 */
function formatDate(date) {
  return date.toISOString().split("T")[0];
}

/**
 * ✅ Helper: Generate a date range array (inclusive)
 */
function getDateRange(startDate, endDate) {
  const dates = [];
  const current = new Date(startDate);
  const last = new Date(endDate);

  while (current <= last) {
    dates.push(formatDate(new Date(current)));
    current.setDate(current.getDate() + 1);
  }

  return dates;
}

/**
 * ✅ Main Function: checkAvailability
 * Checks the "daily_summary" collection for each date
 * Uses the "max_pets_allowed" field from the service document.
 */
exports.checkAvailability = onRequest({ cors: true }, async (req, res) => {
  const { serviceId, startDate, endDate } = req.query;

  if (!serviceId || !startDate || !endDate) {
    return res.status(400).json({
      error: "Missing required query parameters: serviceId, startDate, endDate",
    });
  }

  try {
    const serviceRef = db.collection("users-sp-boarding").doc(serviceId);
    const serviceSnap = await serviceRef.get();

    if (!serviceSnap.exists) {
      return res.status(404).json({ error: "Service not found" });
    }

    const serviceData = serviceSnap.data();
    // ⚠️ Firestore stores max_pets_allowed as a string — convert to number safely
    const maxPetsAllowed = parseInt(serviceData.max_pets_allowed, 10) || 0;

    if (maxPetsAllowed <= 0) {
      return res.status(400).json({
        error: "Invalid or missing max_pets_allowed value in service document",
      });
    }

    const dateList = getDateRange(startDate, endDate);
    const availability = [];

    for (const date of dateList) {
      const summaryRef = serviceRef.collection("daily_summary").doc(date);
      const summarySnap = await summaryRef.get();

      const bookedPets = summarySnap.exists
        ? parseInt(summarySnap.data().bookedPets || 0, 10)
        : 0;

      const spotsLeft = Math.max(maxPetsAllowed - bookedPets, 0);
      const available = spotsLeft > 0;

      availability.push({
        date,
        available,
        spotsLeft,
      });
    }

    return res.status(200).json(availability);
  } catch (error) {
    console.error("Error checking availability:", error);
    return res.status(500).json({ error: "Internal Server Error" });
  }
});
