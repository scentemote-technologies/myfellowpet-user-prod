const { onCall } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { OpenAI } = require("openai");

// 1. Define the secret (this creates a reference, doesn't fetch value yet)
const openAiApiKey = defineSecret("OPENAI_API_KEY");

exports.chatWithAI = onCall(
  // 2. IMPORTANT: You must allow the function to access the secret here
  {
    cors: true,
    secrets: [openAiApiKey]
  },
  async (request) => {
    // 3. Initialize OpenAI inside the function using .value()
    const openai = new OpenAI({ apiKey: openAiApiKey.value() });

    // Extract user message
    // Note: 'request.data' is how you access body in onCall
    const messages = request.data.messages || [];

    try {
        const response = await openai.chat.completions.create({
            model: "gpt-4o", // or "gpt-3.5-turbo" for cheaper testing
            messages: messages,
        });

        return {
            success: true,
            reply: response.choices[0].message.content
        };

    } catch (error) {
        console.error("OpenAI Error:", error);
        // Return a clean error to the Flutter app
        return {
            success: false,
            error: error.message
        };
    }
});