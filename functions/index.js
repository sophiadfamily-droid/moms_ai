/* eslint-disable max-len */

const {onRequest} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");

const systemPrompt = require("./brain/systemPrompt");
const shoppingDictionary = require("./brain/shoppingDictionary");
const taskDictionary = require("./brain/taskDictionary");
const eventDictionary = require("./brain/eventDictionary");
const memoryRules = require("./brain/memoryRules");
const priorities = require("./brain/priorities");
const {detectIntent} = require("./brain/engines/intentDetector");

const {generateZeliaResponse} = require("./services/openaiService");

const openaiApiKey = defineSecret("OPENAI_API_KEY");

/**
 * Construit le contexte cerveau de Zelia.
 * @return {string}
 */
function buildBrainContext() {
  return `
==================================================
SHOPPING DICTIONARY
==================================================

${JSON.stringify(shoppingDictionary)}

==================================================
TASK DICTIONARY
==================================================

${JSON.stringify(taskDictionary)}

==================================================
EVENT DICTIONARY
==================================================

${JSON.stringify(eventDictionary)}

==================================================
MEMORY RULES
==================================================

${JSON.stringify(memoryRules)}

==================================================
PRIORITIES
==================================================

${JSON.stringify(priorities)}
`;
}

exports.chatWithZeliaHttp = onRequest(
    {
      cors: true,
      region: "us-central1",
      secrets: [openaiApiKey],
    },
    async (req, res) => {
      try {
        const message = req.body.message || "";
        const profile = req.body.profile || {};
        const profileContext = req.body.profileContext || {};
        const memories = req.body.memories || [];
        const memoryReasoning = req.body.memoryReasoning || [];
        const events = req.body.events || [];

        const today = new Date().toISOString().slice(0, 10);
        const detectedIntent = detectIntent(message);

        const systemContent = `
${systemPrompt({
    today,
    profile,
    profileContext,
    memories,
    memoryReasoning,
    events,
    detectedIntent,
  })}

${buildBrainContext()}
`;

        const parsed = await generateZeliaResponse({
          apiKey: openaiApiKey.value(),
          systemContent,
          userMessage: message,
        });

        res.json({
          reply: parsed.reply || "C'est noté 💕",
          actions: parsed.actions || [],
          memories: parsed.memories || [],
        });
      } catch (error) {
        console.error("ZELIA ERROR :", error);

        res.status(500).json({
          reply: "Je rencontre un petit souci 💕",
          actions: [],
          memories: [],
        });
      }
    },
);
