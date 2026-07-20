const {
  onCall,
  onRequest,
} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");

const {
  handleChatRequest,
} = require("./services/chatRequestHandler");
const {
  createCallableChatHandler,
  createCallableFunctionOptions,
  createHttpChatHandler,
  createHttpFunctionOptions,
  OPENAI_API_KEY_NAME,
} = require("./services/chatTransportAdapters");

const openaiApiKey = defineSecret(OPENAI_API_KEY_NAME);

const sharedDependencies = {
  handleChatRequest,
  getApiKey: () => openaiApiKey.value(),
};

exports.chatWithZeliaHttp = onRequest(
    createHttpFunctionOptions(openaiApiKey),
    createHttpChatHandler(sharedDependencies),
);

exports.chatWithZeliaCallable = onCall(
    createCallableFunctionOptions(openaiApiKey),
    createCallableChatHandler(sharedDependencies),
);
