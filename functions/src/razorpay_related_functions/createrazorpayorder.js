const functions = require("firebase-functions");
const express = require("express");
const Razorpay = require("razorpay");

const app = express();
app.use(express.json());

// Health check endpoint
app.get("/", (req, res) => {
  res.send("Hello from Express!");
});

// Initialize Razorpay instance with your live credentials
const razorpayInstance = new Razorpay({
  key_id: "rzp_live_mz8YAAQd3HiLXz", // Replace with your live key
  key_secret: "r7Rjy3E1ZbNXagWSLcRgaeHz", // Replace with your live secret
});

// Endpoint to create an order
app.post("/createOrder", async (req, res) => {
  try {
    const {amount, currency = "INR", receipt = "receipt#1"} = req.body;
    const options = {
      amount, // amount in paise
      currency,
      receipt,
      payment_capture: 1,
    };
    const order = await razorpayInstance.orders.create(options);
    res.json({success: true, order});
  } catch (err) {
    res.status(500).json({success: false, error: err.message});
  }
});

// Export the Express app as an HTTPS function
exports.createRazorpayOrder = functions.https.onRequest(app);
