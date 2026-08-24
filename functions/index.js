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
const {
  zeliaEnforceAppCheck,
} = require("./services/securityEnvironment");
const {consumeChatQuota} = require("./services/chatQuotaService");
const {
  analyzeStructuredScheduleDocument,
} = require("./services/structuredScheduleDocumentAnalysisService");
const {
  createCallableScheduleDocumentHandler,
} = require("./services/structuredScheduleDocumentTransport");
const {
  createCallableAccountDataHandler,
} = require("./services/accountDataLifecycleService");
const {
  loadCanonicalShoppingItems,
} = require("./services/canonicalShoppingRepository");

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
    createCallableFunctionOptions(openaiApiKey, zeliaEnforceAppCheck),
    createCallableChatHandler({
      ...sharedDependencies,
      handlerDependencies: {
        loadShoppingItems: ({uid, limit}) => loadCanonicalShoppingItems({
          firestore,
          uid,
          limit,
        }),
      },
      appCheckEnforcement: zeliaEnforceAppCheck,
      consumeQuota: ({uid}) => consumeChatQuota({firestore, uid}),
    }),
);

exports.analyzeStructuredScheduleDocumentCallable = onCall(
    createCallableFunctionOptions(openaiApiKey, zeliaEnforceAppCheck),
    createCallableScheduleDocumentHandler({
      analyzeDocument: analyzeStructuredScheduleDocument,
      getApiKey: () => openaiApiKey.value(),
      appCheckEnforcement: zeliaEnforceAppCheck,
      consumeQuota: ({uid}) => consumeChatQuota({firestore, uid}),
    }),
);

exports.manageAccountDataCallable = onCall(
    {
      region: "us-central1",
      timeoutSeconds: 120,
      enforceAppCheck: zeliaEnforceAppCheck,
    },
    createCallableAccountDataHandler({firestore}),
);
