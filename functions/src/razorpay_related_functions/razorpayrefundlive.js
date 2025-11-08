const {onRequest} = require("firebase-functions/v2/https");
const fetch = require("node-fetch");

exports.razorpayRefundLive = onRequest(
    {cors: true},
    async (req, res) => {
      // Validate request: it must be a POST request with a paymentId.
      if (req.method !== "POST" || !req.body.paymentId) {
        return res.status(400).json({error: "Invalid request."});
      }

      const paymentId = req.body.paymentId;

      // Hardcoded Razorpay live credentials
      const razorpayKey = "rzp_live_mz8YAAQd3HiLXz";
      const razorpaySecret = "r7Rjy3E1ZbNXagWSLcRgaeHz";

      // Create the Basic auth header.
      const credentials = `${razorpayKey}:${razorpaySecret}`;
      const encodedCredentials = Buffer.from(credentials).toString("base64");
      const auth = "Basic " + encodedCredentials;

      const url = `https://api.razorpay.com/v1/payments/${paymentId}/refund`;

      try {
        const response = await fetch(url, {
          method: "POST",
          headers: {
            "Authorization": auth,
            "Content-Type": "application/json",
          },
        });

        if (response.ok) {
          const data = await response.json();
          return res.status(200).json({refund: data});
        } else {
          const errorData = await response.json();
          return res.status(response.status).json({error: errorData});
        }
      } catch (error) {
        return res.status(500).json({error: error.toString()});
      }
    },
);
