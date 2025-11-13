const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

// Initialize Firebase Admin
initializeApp();
const db = getFirestore();

// --- [HELPER 1: Ported from your Dart code] ---
// This is your _slugify function in JavaScript
function slugify(input) {
  if (!input) return '';
  return input
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-') // Replaces non-alphanumeric with hyphens
    .replace(/^-+|-+$/g, '');     // Trims hyphens from start/end
}

// --- [HELPER 2: Ported from your Dart code] ---
// This is your _buildSeoUrl function in JavaScript
// It assumes 'service' is the raw data object from Firestore
function buildSeoUrl(service) {
  const country = 'india';
  const serviceType = 'boarding';

  // Get data from the Firestore object, using your fallbacks
  const state = slugify(service.state || 'unknown-state');
  const district = slugify(service.district || 'unknown-district');
  const area = slugify(service.area_name || 'unknown-area'); // Firestore uses snake_case
  const shopName = slugify(service.shop_name || 'pet-service'); // Firestore uses snake_case

  // Get the first pet type, or 'pet' as a fallback
  const pet = slugify((service.pets && service.pets.length > 0) ? service.pets[0] : 'pet');

  return `/${country}/${serviceType}/${state}/${district}/${area}/${shopName}-${pet}-center`;
}

/**
 * [HELPER 3: Same as before]
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

// --- YOUR MAIN AI FUNCTION (UPDATED) ---
exports.searchBoarders = onRequest(
  { cors: true }, // Allow chat.openai.com to call this
  async (req, res) => {

  const { location, petType } = req.query;

  try {
    let query = db.collection('users-sp-boarding')
                  .where('display', '==', true);

    if (location) {
      query = query.where('area_name', '==', location);
    }
    if (petType) {
      query = query.where('pets', 'array-contains', petType.toLowerCase());
    }

    const snapshot = await query.limit(10).get();

    if (snapshot.empty) {
      return res.status(200).json([]);
    }

    const finalResults = [];
    for (const doc of snapshot.docs) {
      const service = doc.data();
      const rating = await fetchRatingStats(service.service_id);

      // --- ⭐️ THIS IS THE UPDATE ⭐️ ---
      // We now call your buildSeoUrl logic to create the URL
      const seoPath = buildSeoUrl(service);
      const fullUrl = `https://myfellowpet.com${seoPath}`; // ⚠️ Update with your domain
      // --- ⭐️ END OF UPDATE ⭐️ ---

      finalResults.push({
        serviceId: service.service_id || doc.id, // ✅ Add real Firestore ID
        name: service.shop_name,
        area: service.area_name,
        minPrice: service.min_price || 0,
        isCertified: service.mfp_certified || false,
        rating: rating.avg,
        ratingCount: rating.count,
        url: fullUrl // We pass the new, correct URL
      });
    }

    return res.status(200).json(finalResults);

  } catch (error) {
    console.error("Error in searchBoarders:", error);
    return res.status(500).send("Internal Server Error");
  }
});