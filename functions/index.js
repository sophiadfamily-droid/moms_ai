const {
  onCall,
} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {getApps, initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const {
  handleChatRequest,
} = require("./services/chatRequestHandler");
const {
  createCallableChatHandler,
  createCallableFunctionOptions,
  OPENAI_API_KEY_NAME,
} = require("./services/chatTransportAdapters");
const {consumeChatQuota} = require("./services/chatQuotaService");

if (getApps().length === 0) {
  initializeApp();
}
const firestore = getFirestore();

const openaiApiKey = defineSecret(OPENAI_API_KEY_NAME);

const sharedDependencies = {
  handleChatRequest,
  getApiKey: () => openaiApiKey.value(),
};

exports.chatWithZeliaCallable = onCall(
    createCallableFunctionOptions(openaiApiKey),
    createCallableChatHandler({
      ...sharedDependencies,
      consumeQuota: ({uid}) => consumeChatQuota({firestore, uid}),
    }),
);
