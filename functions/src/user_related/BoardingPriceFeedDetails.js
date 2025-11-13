const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

/**
 * ✅ getPricingDetails
 * Reads actual Firestore fields (rates_daily, walking_rates, etc.)
 * and returns structured, typed numeric data for the GPT or app.
 */
exports.getPricingDetails = onRequest({ cors: true }, async (req, res) => {
  const { serviceId, petType } = req.query;

  if (!serviceId || !petType) {
    return res.status(400).json({
      error: "Missing required parameters: serviceId and petType",
    });
  }

  try {
    const petRef = db
      .collection("users-sp-boarding")
      .doc(serviceId)
      .collection("pet_information")
      .doc(petType.toLowerCase());

    const petSnap = await petRef.get();

    if (!petSnap.exists) {
      return res.status(404).json({ error: "Pet information not found" });
    }

    const petData = petSnap.data();
    const toNumMap = (map) => {
      const result = {};
      if (map && typeof map === "object") {
        Object.entries(map).forEach(([k, v]) => {
          const num = parseFloat(v);
          result[k] = isNaN(num) ? 0 : num;
        });
      }
      return result;
    };

    const response = {
      petType: petType,
      acceptedSizes: petData.accepted_sizes || [],
      acceptedBreeds: petData.accepted_breeds || [],
      rates: {
        boarding: toNumMap(petData.rates_daily),
        walking: toNumMap(petData.walking_rates),
        meal: toNumMap(petData.meal_rates),
      },
      offerRates: {
        boarding: toNumMap(petData.offer_daily_rates),
        walking: toNumMap(petData.offer_walking_rates),
        meal: toNumMap(petData.offer_meal_rates),
      },
      totals: toNumMap(petData.total_prices),
      offerTotals: toNumMap(petData.total_offer_prices),
      feedingDetails: petData.feeding_details || {},
    };

    return res.status(200).json(response);
  } catch (error) {
    console.error("Error fetching pricing details:", error);
    return res.status(500).json({ error: "Internal Server Error" });
  }
});
