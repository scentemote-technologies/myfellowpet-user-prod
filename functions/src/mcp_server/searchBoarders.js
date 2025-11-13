// Import the necessary Firebase modules
const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

// Initialize Firebase Admin
initializeApp();
const db = getFirestore();

/**
 * Helper function to parse dates.
 * Generates an array of all dates between start and end.
 */
function getDatesInRange(startDate, endDate) {
  const dates = [];
  let currentDate = new Date(startDate);
  const stopDate = new Date(endDate);

  while (currentDate <= stopDate) {
    // We only care about the date part, not time, so we use YYYY-MM-DD
    dates.push(new Date(currentDate.toISOString().split('T')[0]));
    currentDate.setDate(currentDate.getDate() + 1);
  }
  return dates;
}

/**
 * [PORTED FROM YOUR APP]
 * Checks if a single service is available based on your logic.
 */
async function isServiceAvailable(serviceId, maxAllowed, petCount, filterDates) {
  if (petCount === 0 || filterDates.length === 0) {
    return true; // No availability filter applied
  }

  const dailySummaryRef = db.collection('users-sp-boarding')
                            .doc(serviceId)
                            .collection('daily_summary');

  try {
    // Create a map of { 'YYYY-MM-DD': { bookedPets: X, isHoliday: Y } }
    const bookingCounts = {};
    const summarySnapshot = await dailySummaryRef.get();
    summarySnapshot.forEach(doc => {
      // doc.id is 'YYYY-MM-DD'
      bookingCounts[doc.id] = doc.data();
    });

    // Check each date the user requested
    for (const date of filterDates) {
      const dateString = date.toISOString().split('T')[0];
      const summary = bookingCounts[dateString];

      let usedSlots = 0;
      if (summary) {
        // Your logic: A holiday means it's full (999)
        if (summary.isHoliday === true) {
          usedSlots = 999;
        } else {
          usedSlots = summary.bookedPets || 0;
        }
      }

      // The core check from your isolate filter
      if (usedSlots + petCount > maxAllowed) {
        return false; // This date is full
      }
    }

    return true; // All dates are available
  } catch (error) {
    console.error(`Error checking availability for ${serviceId}:`, error);
    return false; // Fail safe
  }
}

/**
 * [PORTED FROM YOUR APP]
 * Fetches the rating for a service.
 */
async function fetchRatingStats(serviceId) {
  const reviewsRef = db.collection('public_review')
                       .doc('service_providers')
                       .collection('sps')
                       .doc(serviceId)
                       .collection('reviews');

  const snap = await reviewsRef.get();
  if (snap.empty) {
    return { avg: 0, count: 0 };
  }

  const ratings = snap.docs
    .map(d => d.data().rating || 0)
    .filter(r => r > 0);

  const count = ratings.length;
  const avg = count > 0
    ? ratings.reduce((a, b) => a + b, 0) / count
    : 0;

  return {
    avg: parseFloat(avg.toFixed(1)),
    count: count,
  };
}


// --- THE MAIN CLOUD FUNCTION ---

exports.searchBoarders = onRequest(
  { cors: true }, // Enable CORS so the AI can call it
  async (req, res) => {

  // --- Step 1: Get Query Parameters from the AI ---
  // Example: /searchBoarders?location=Koramangala&petType=dog
  const {
    location,     // string: "Koramangala"
    petType,      // string: "dog"
    petCount,     // string: "1"
    startDate,    // string: "2025-11-21"
    endDate,      // string: "2025-11-23"
    isCertified,  // string: "true"
    isOffer,      // string: "true"
    searchQuery   // string: "HappyTails"
  } = req.query;

  const filterPetCount = parseInt(petCount || "0", 10);
  const filterDates = (startDate && endDate)
    ? getDatesInRange(startDate, endDate)
    : [];

  try {
    // --- Step 2: Build Base Firestore Query ---
    // This is based on your BoardingCardsProvider
    let query = db.collection('users-sp-boarding')
                  .where('display', '==', true);

    // Apply simple filters that Firestore supports well
    if (location) {
      // Your code filters on areaName, so we'll do the same.
      query = query.where('area_name', '==', location);
    }
    if (petType) {
      query = query.where('pets', 'array-contains', petType.toLowerCase());
    }
    if (isCertified === "true") {
      query = query.where('mfp_certified', '==', true);
    }
    if (isOffer === "true") {
      query = query.where('isOfferActive', '==', true);
    }

    // --- Step 3: Fetch Initial Docs ---
    const snapshot = await query.get();
    if (snapshot.empty) {
      return res.status(200).json([]);
    }

    let potentialServices = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data()
    }));

    // --- Step 4: In-Memory Filtering (Just like your isolate) ---
    const filteredServices = [];

    // We must check availability one-by-one
    for (const service of potentialServices) {

      // A) Search Query Filter
      if (searchQuery) {
        const name = (service.shop_name || "").toLowerCase();
        if (!name.includes(searchQuery.toLowerCase())) {
          continue; // Skip this service
        }
      }

      // B) Availability Filter (The hard one)
      const maxAllowed = parseInt(service.max_pets_allowed || "0", 10);
      const isAvailable = await isServiceAvailable(
        service.id,
        maxAllowed,
        filterPetCount,
        filterDates
      );

      if (!isAvailable) {
        continue; // Skip this service
      }

      // If we're here, the service passed all filters!
      filteredServices.push(service);
    }

    // --- Step 5: Format the final data for the AI ---
    const finalResults = [];
    for (const service of filteredServices) {
      // Get the rating
      const rating = await fetchRatingStats(service.service_id);

      finalResults.push({
        name: service.shop_name,
        area: service.area_name,
        // Your code uses min_price/max_price which are pre-calculated
        minPrice: service.min_price || 0,
        maxPrice: service.max_price || 0,
        isOffer: service.isOfferActive || false,
        isCertified: service.mfp_certified || false,
        rating: rating.avg,
        ratingCount: rating.count,
        // We give the AI a direct link to the *public page*
        // This is your SEO strategy from 10/18!
        url: `https://your-domain.com/boarding/${service.id}`
      });
    }

    // --- Step 6: Send the JSON response ---
    return res.status(200).json(finalResults);

  } catch (error) {
    console.error("Error in searchBoarders function:", error);
    return res.status(500).send("Internal Server Error");
  }
});