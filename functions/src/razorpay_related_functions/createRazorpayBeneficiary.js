import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { defineSecret } from "firebase-functions/params";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import Razorpay from "razorpay";

initializeApp();
const db = getFirestore();

// 🔐 Google-managed secrets
const razorpayKeyId = defineSecret("RAZORPAY_TEST_KEY_ID");
const razorpayKeySecret = defineSecret("RAZORPAY_TEST_KEY_SECRET");

export const createRazorpayBeneficiary = onDocumentWritten(
  {
    document: "users-sp-boarding/{spId}",
    region: "asia-south1",
    secrets: [razorpayKeyId, razorpayKeySecret],
  },
  async (event) => {
    const before = event.data?.before?.data() || {};
    const after = event.data?.after?.data() || {};
    const spId = event.params.spId;

    // 🛑 Exit early if no new bank details were added
    if (!before.bank_account_num && !after.bank_account_num) return;

    try {
      console.log(`🚀 Creating Razorpay beneficiary for SP: ${spId}`);

      const razorpay = new Razorpay({
        key_id: razorpayKeyId.value(),
        key_secret: razorpayKeySecret.value(),
      });

      // 1️⃣ Create Contact
      const contact = await razorpay.contacts.create({
        name: after.owner_name || "Unknown Partner",
        email: after.notification_email || "noreply@myfellowpet.com",
        contact: after.phoneNumber || "",
        type: "vendor",
      });
      console.log(`✅ Contact created: ${contact.id}`);

      // 2️⃣ Create Fund Account
      const fundAccount = await razorpay.fundAccounts.create({
        contact_id: contact.id,
        account_type: "bank_account",
        bank_account: {
          name: after.owner_name,
          ifsc: after.bank_ifsc,
          account_number: after.bank_account_num,
        },
      });
      console.log(`✅ Fund account created: ${fundAccount.id}`);

      // 3️⃣ Save result in Firestore
      await db.collection("users-sp-boarding").doc(spId).update({
        razorpay_contact_id: contact.id,
        razorpay_fund_account_id: fundAccount.id,
        bank_verified: true,
        razorpay_status: "verified",
        updated_at: new Date().toISOString(),
      });

      console.log(`🔥 Beneficiary successfully linked for ${spId}`);
    } catch (err) {
      console.error(`❌ Razorpay creation failed for ${spId}:`, err);
      await db.collection("users-sp-boarding").doc(spId).update({
        bank_verified: false,
        razorpay_status: "failed",
        razorpay_error: err.message || "Unknown error",
      });
    }
  }
);
