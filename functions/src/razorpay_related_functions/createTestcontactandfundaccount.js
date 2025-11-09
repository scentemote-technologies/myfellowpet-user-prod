const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const express = require("express");
const cors = require("cors");
const axios = require("axios");

// 🔐 Securely load Razorpay Test Keys from Secrets
const RZP_KEY = defineSecret("RAZORPAY_TEST_PAYOUT_KEY");
const RZP_SECRET = defineSecret("RAZORPAY_TEST_PAYOUT_SECRET");

// Initialize Firebase Admin
admin.initializeApp();

const app = express();
app.use(cors({ origin: true }));
app.use(express.json());

// Health-check endpoint
app.get("/", (_req, res) => res.status(200).send("OK"));

// Main endpoint: create contact + fund account + verify
app.post("/", async (req, res) => {
  const {
    reference_id,
    name,
    email,
    contact,
    account_number,
    ifsc,
    account_type = "bank_account",
  } = req.body;

  if (!reference_id || !name || !email || !contact || !account_number || !ifsc) {
    return res
      .status(400)
      .send("reference_id + name + email + contact + account_number + ifsc required");
  }

  try {
    // 🔹 Load Razorpay SDK dynamically after secrets are available
    const { Contact, FundAccount } = require("razorpayx-nodejs-sdk")(
      RZP_KEY.value(),
      RZP_SECRET.value()
    );

    console.log("🔹 Creating Contact for shop", reference_id);
    const savedContact = await Contact.create({
      name,
      email,
      contact,
      type: "vendor",
      reference_id,
    });
    console.log("✅ Contact created:", savedContact.id);

    await admin
      .firestore()
      .collection("users-sp-boarding")
      .doc(reference_id)
      .update({ payout_contact_id: savedContact.id });

    console.log("🔹 Creating Fund Account under Contact", savedContact.id);
    const savedFA = await FundAccount.create({
      contact_id: savedContact.id,
      account_type,
      bank_account: { name, ifsc, account_number },
    });
    console.log("✅ Fund Account created:", savedFA.id);

    // 🔹 Verify bank account (penny drop)
    const auth = {
      username: RZP_KEY.value(),
      password: RZP_SECRET.value(),
    };

    console.log("🔹 Verifying bank account...");
    const verifyResponse = await axios.post(
      "https://api.razorpay.com/v1/fund_accounts/validations",
      {
        account_number,
        ifsc,
        name,
        fund_account: { id: savedFA.id },
        amount: 100, // ₹1 (100 paise)
        currency: "INR",
      },
      { auth }
    );

    const verificationResult = verifyResponse.data;
    console.log("✅ Verification result:", verificationResult);

    const verifiedName =
      verificationResult?.recipient_name ||
      verificationResult?.entity?.bank_account?.name ||
      name;

    await admin
      .firestore()
      .collection("users-sp-boarding")
      .doc(reference_id)
      .update({
        payout_fund_account_id: savedFA.id,
        bank_verified: verificationResult.status === "completed",
        verified_name: verifiedName,
        verification_response: verificationResult,
      });

    console.log("✅ Verification info saved to Firestore");

    return res.json({
      contact_id: savedContact.id,
      fund_account_id: savedFA.id,
      verification: verificationResult,
    });
  } catch (err) {
    console.error(
      "🔥 Error in createContactAndFundAccount:",
      err.response?.data || err.message
    );
    return res.status(500).send(err.response?.data || err.toString());
  }
});

// Export function with secrets
exports.createContactAndFundAccount = onRequest(
  {
    region: "asia-south1",
    secrets: [RZP_KEY, RZP_SECRET],
  },
  app
);
