const {onRequest} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const Razorpay = require("razorpay");

// reference your test‐key secrets
const razorpayTestKeyId = defineSecret("RAZORPAY_TEST_KEY_ID");
const razorpayTestKeySecret = defineSecret("RAZORPAY_TEST_KEY_SECRET");

exports.initiateTestRazorpayRefund = onRequest(
    {
      region: "us-central1", // or your preferred region
      cors: true, // automatic CORS
      secrets: [razorpayTestKeyId, razorpayTestKeySecret],
    },
    async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).send("Only POST allowed");
      }
      const {payment_id: paymentId, amount, notes} = req.body;
      if (!paymentId || !amount) {
        return res.status(400).json({error: "paymentId & amount are required"});
      }

      // initialize Razorpay client with your test keys
      const razorpay = new Razorpay({
        key_id: await razorpayTestKeyId.value(),
        key_secret: await razorpayTestKeySecret.value(),
      });

      try {
        const options = {amount};
        if (notes) options.notes = notes;
        const refund = await razorpay.payments.refund(paymentId, options);
        const payload = {
          refund_id: refund.id,
          ...refund
        };
        return res.status(200).json(payload);
      } catch (err) {
        console.error("Test‐refund error:", err);
        const msg = (err.error && err.error.description) || err.message;
        return res.status(500).json({error: msg});
      }
    },
);
