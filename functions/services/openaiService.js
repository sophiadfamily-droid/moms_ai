const {OpenAI} = require("openai");

/**
 * Génère une réponse Zelia via OpenAI.
 * @param {Object} params paramètres de génération
 * @return {Promise<Object>}
 */
async function generateZeliaResponse({
  apiKey,
  systemContent,
  userMessage,
}) {
  const openai = new OpenAI({
    apiKey,
  });

  const completion = await openai.chat.completions.create({
    model: "gpt-4.1-mini",

    response_format: {
      type: "json_object",
    },

    messages: [
      {
        role: "system",
        content: systemContent,
      },
      {
        role: "user",
        content: userMessage,
      },
    ],

    temperature: 0.03,
    max_tokens: 2600,
  });

  const content = completion.choices[0].message.content;
  return JSON.parse(content);
}

module.exports = {
  generateZeliaResponse,
};
