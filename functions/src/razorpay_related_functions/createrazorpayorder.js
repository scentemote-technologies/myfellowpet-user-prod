const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const express = require("express");
const Razorpay = require("razorpay");

const app = express();
app.use(express.json());

// --- 🔐 Load secrets securely from Firebase Secret Manager ---
const RAZORPAY_LIVE_KEY = defineSecret("RAZORPAY_LIVE_KEY");
const RAZORPAY_LIVE_SECRET = defineSecret("RAZORPAY_LIVE_SECRET");

// --- ✅ Health Check Endpoint ---
app.get("/", (req, res) => {
  res.send("🐾 MyFellowPet Razorpay order service is live!");
});

// --- 💳 Main Order Creation Endpoint ---
app.post("/createOrder", async (req, res) => {
  try {
    const { amount, currency = "INR", receipt = "receipt#1" } = req.body;

    if (!amount) {
      return res.status(400).json({ success: false, error: "Amount is required" });
    }

    // Initialize Razorpay using secrets
    const razorpayInstance = new Razorpay({
      key_id: RAZORPAY_LIVE_KEY.value(),
      key_secret: RAZORPAY_LIVE_SECRET.value(),
    });

    const options = {
      amount, // Amount in paise
      currency,
      receipt,
      payment_capture: 1,
    };

    const order = await razorpayInstance.orders.create(options);
    res.json({ success: true, order });
  } catch (error) {
    console.error("Error creating Razorpay order:", error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// --- 🚀 Export the Function Securely ---
exports.createRazorpayOrder = onRequest(
  {
    cors: true,
    secrets: [RAZORPAY_LIVE_KEY, RAZORPAY_LIVE_SECRET],
  },
  app
);
