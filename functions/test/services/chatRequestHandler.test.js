const assert = require("node:assert/strict");
const test = require("node:test");

const {
  OPENAI_TIMEOUT_MS,
  handleChatRequest,
  runWithOpenAiDeadline,
} = require("../../services/chatRequestHandler");
const {generateZeliaResponse} = require("../../services/openaiService");

/**
 * Builds a canonical bounded conversation request fixture.
 * @param {string} message Visible user message.
 * @return {object} Canonical request.
 */
function request(message = "Ajoute du lait aux courses") {
  return {
    schemaVersion: 2,
    correlationId: "0123456789abcdef0123456789abcdef",
    message,
    sessionGeneration: 0,
    conversationContext: {
      schemaVersion: 1,
      projectionVersion: 1,
      purpose: "conversation.transport.v1",
      generatedAt: "2026-07-20T10:00:00.000Z",
      state: "complete",
      sections: [],
      budgetRequested: 245,
      budgetUsed: 0,
      omittedCount: 0,
      truncatedSections: [],
      warningCodes: [],
      redactionVersion: 1,
    },
    conversationHistory: [],
    profile: {},
    profileContext: {},
    memories: [],
    memoryReasoning: [],
    events: [],
    autonomyPolicyVersion: 1,
    autonomyMode: "suggestions",
    allowedStructuredResponseKinds: [
      "answer", "answerWithCaveat", "clarificationRequired",
      "confirmationRequired", "actionProposal", "cannotDetermine",
      "contextUnavailable", "unsupportedRequest", "safeFailure",
    ],
  };
}

const payload = request();

/**
 * Builds a valid model response fixture.
 * @param {string} visibleText Visible assistant text.
 * @param {Array<object>} actions Structured actions.
 * @return {object} Closed epistemic response.
 */
function response(visibleText, actions = []) {
  return {
    visibleText,
    actions,
    memories: [],
    epistemic: {
      schemaVersion: 1,
      responseKind: actions.length > 0 ? "actionProposal" : "answer",
      epistemicState: "grounded",
      confidenceLevel: "high",
      usedSourceTypes: ["currentUserMessage"],
      groundingReferences: [{
        schemaVersion: 1,
        sourceType: "currentUserMessage",
        section: null,
        factKey: null,
        freshness: "current",
        confirmation: "confirmed",
        projectionVersion: 0,
      }],
      personalClaims: [],
      missingInformation: [],
      contradictions: [],
      clarification: null,
      uncertaintyCodes: [],
      contextStateObserved: "complete",
      warningCodes: [],
      responseId: "response-test",
    },
  };
}

/**
 * Builds confirmed primary, partner, and child profile context.
 * @param {string} message Visible user question.
 * @return {object} Canonical request with Human and Relation sections.
 */
function personalProfileRequest(message) {
  const value = request(message);
  value.conversationContext.sections = [
    {
      type: "human",
      availability: "available",
      freshness: "current",
      items: [
        {
          type: "person",
          confirmation: "confirmed",
          freshness: "current",
          facts: {
            nodeId: "human:person:person-main",
            personRole: "primary",
            displayName: "Sophia",
            birthDate: "1990-02-02",
          },
        },
        {
          type: "person",
          confirmation: "confirmed",
          freshness: "current",
          facts: {
            nodeId: "human:person:person-willy",
            personRole: "related",
            displayName: "Willy",
            birthDate: "1991-10-22",
          },
        },
        {
          type: "person",
          confirmation: "confirmed",
          freshness: "current",
          facts: {
            nodeId: "human:person:person-kassim",
            personRole: "related",
            displayName: "Kassim",
            birthDate: "2022-04-10",
          },
        },
      ],
      budgetLimit: 55,
      budgetUsed: 12,
      omittedCount: 0,
      truncated: false,
    },
    {
      type: "relation",
      availability: "available",
      freshness: "current",
      items: [
        {
          type: "relation",
          confirmation: "confirmed",
          freshness: "current",
          facts: {
            relationRole: "spouse",
            sourceNodeId: "human:person:person-main",
            targetNodeId: "human:person:person-willy",
          },
        },
        {
          type: "relation",
          confirmation: "confirmed",
          freshness: "current",
          facts: {
            relationRole: "child",
            sourceNodeId: "human:person:person-main",
            targetNodeId: "human:person:person-kassim",
          },
        },
      ],
      budgetLimit: 50,
      budgetUsed: 6,
      omittedCount: 0,
      truncated: false,
    },
  ];
  value.conversationContext.budgetUsed = 18;
  return value;
}

/**
 * Builds profile context with day-specific work and family schedules.
 * @param {string} message Visible user question.
 * @return {object} Canonical request with typed routine items.
 */
function scheduledProfileRequest(message) {
  const value = personalProfileRequest(message);
  value.conversationContext.sections.push({
    type: "routine",
    availability: "available",
    freshness: "current",
    items: [
      {
        type: "routine",
        confirmation: "confirmed",
        freshness: "current",
        facts: {
          routineKind: "workSchedule",
          subjectNodeId: "human:person:person-main",
          title: "Travail matin",
          days: "Lundi",
          startTime: "09:00",
          endTime: "12:00",
        },
      },
      {
        type: "routine",
        confirmation: "confirmed",
        freshness: "current",
        facts: {
          routineKind: "workSchedule",
          subjectNodeId: "human:person:person-main",
          title: "Travail après-midi",
          days: "Mercredi",
          startTime: "14:00",
          endTime: "17:00",
        },
      },
      {
        type: "routine",
        confirmation: "confirmed",
        freshness: "current",
        facts: {
          routineKind: "workSchedule",
          subjectNodeId: "human:person:person-willy",
          title: "Travail",
          days: "Mardi",
          startTime: "08:00",
          endTime: "16:00",
        },
      },
      {
        type: "routine",
        confirmation: "confirmed",
        freshness: "current",
        facts: {
          routineKind: "personalActivity",
          subjectNodeId: "human:person:person-main",
          title: "Pilate",
          days: "Lundi",
          startTime: "18:00",
          endTime: "19:00",
        },
      },
      {
        type: "routine",
        confirmation: "confirmed",
        freshness: "current",
        facts: {
          routineKind: "personalActivity",
          subjectNodeId: "human:person:person-main",
          title: "Natation",
          days: "Mercredi",
          startTime: "10:00",
          endTime: "11:00",
        },
      },
      {
        type: "routine",
        confirmation: "confirmed",
        freshness: "current",
        facts: {
          routineKind: "schoolSchedule",
          subjectNodeId: "human:person:person-kassim",
          title: "École",
          days: "Mardi,Lundi",
          startTime: "08:30",
          endTime: "16:30",
        },
      },
      {
        type: "routine",
        confirmation: "confirmed",
        freshness: "current",
        facts: {
          routineKind: "childActivity",
          subjectNodeId: "human:person:person-kassim",
          title: "Football",
          days: "Mercredi",
          startTime: "17:00",
          endTime: "18:00",
        },
      },
    ],
    budgetLimit: 55,
    budgetUsed: 49,
    omittedCount: 0,
    truncated: false,
  });
  value.conversationContext.budgetUsed = 67;
  return value;
}

test("uses a 45 second total OpenAI deadline", () => {
  assert.equal(OPENAI_TIMEOUT_MS, 45000);
});

test("answers shopping directly from the shared brain", async () => {
  const value = request("Qu’est-ce qu’il me reste à acheter ?");
  value.conversationContext.sections = [{
    type: "shopping",
    availability: "available",
    freshness: "current",
    items: [{
      type: "shoppingItem",
      confirmation: "confirmed",
      freshness: "current",
      facts: {
        status: "active",
        title: "Fraises",
        urgency: "1",
        createdAt: "2026-08-24T08:00:00.000Z",
        quantity: "2 barquettes",
      },
    }],
    budgetLimit: 25,
    budgetUsed: 5,
    omittedCount: 0,
    truncated: false,
  }];
  value.conversationContext.budgetUsed = 5;
  let generations = 0;

  const result = await handleChatRequest(value, {uid: "test-uid"}, {
    generateResponse: async () => {
      generations++;
      return response("unexpected");
    },
  });

  assert.equal(generations, 0);
  assert.equal(result.reply,
      "Il te reste à acheter : Fraises (2 barquettes).");
  assert.equal(result.epistemic.personalClaims[0].category, "shoppingFact");
});

test(
    "current phone shopping cannot be replaced by stale server products",
    async () => {
      const value = request("Qu’est-ce qu’il me reste à acheter ?");
      value.conversationContext.sections = [{
        type: "shopping",
        availability: "available",
        freshness: "current",
        items: [{
          type: "shoppingItem",
          confirmation: "confirmed",
          freshness: "current",
          facts: {
            status: "active",
            title: "Bas",
            urgency: "0",
            createdAt: "2026-08-20T08:00:00.000Z",
            quantity: "1",
          },
        }],
        budgetLimit: 25,
        budgetUsed: 5,
        omittedCount: 0,
        truncated: false,
      }];
      value.conversationContext.budgetUsed = 5;

      let serverLoads = 0;
      const result = await handleChatRequest(value, {uid: "verified-user"}, {
        loadShoppingItems: async () => {
          serverLoads++;
          return [{
            title: "Kiwis supprimés",
            quantity: "2",
            isUrgent: false,
            createdAt: "2026-08-24T08:00:00.000Z",
          }];
        },
        generateResponse: async () => response("unexpected"),
      });

      assert.equal(serverLoads, 0);
      assert.equal(result.reply, "Il te reste à acheter : Bas (1).");
      assert.equal(result.reply.includes("Kiwis"), false);
      assert.equal(
          result.epistemic.groundingReferences[0].sourceType,
          "lifeContextShopping",
      );
    },
);

test("never loads stale account shopping when phone context is unavailable",
    async () => {
      const value = request("Qu’est-ce qu’il me reste à acheter ?");
      value.conversationContext.sections = [{
        type: "shopping",
        availability: "unavailable",
        freshness: "unknown",
        items: [],
        budgetLimit: 25,
        budgetUsed: 0,
        omittedCount: 0,
        truncated: false,
      }];
      let generations = 0;
      const loads = [];
      const result = await handleChatRequest(value, {uid: "verified-user"}, {
        loadShoppingItems: async (options) => {
          loads.push(options);
          return [{
            title: "Kiwis",
            quantity: "3",
            isUrgent: true,
            createdAt: "2026-08-24T08:00:00.000Z",
          }];
        },
        generateResponse: async () => {
          generations++;
          return response("unexpected");
        },
      });
      assert.deepEqual(loads, []);
      assert.equal(generations, 0);
      assert.equal(result.reply,
          "Je n’arrive pas à lire ta liste actuelle. " +
          "Ouvre la liste de courses, puis réessaie.");
      assert.equal(result.epistemic.responseKind, "contextUnavailable");
      assert.equal(result.reply.includes("Kiwis"), false);
    });

test("answers an empty account list without using the model", async () => {
  const value = request("Que dois-je encore acheter ?");
  value.conversationContext.sections = [{
    type: "shopping",
    availability: "empty",
    freshness: "current",
    items: [],
    budgetLimit: 25,
    budgetUsed: 0,
    omittedCount: 0,
    truncated: false,
  }];
  let generations = 0;
  const result = await handleChatRequest(value, {uid: "verified-user"}, {
    loadShoppingItems: async () => [],
    generateResponse: async () => {
      generations++;
      return response("unexpected");
    },
  });
  assert.equal(generations, 0);
  assert.equal(result.reply, "Ta liste de courses est vide pour le moment.");
});

test("does not load shopping for an unrelated question", async () => {
  let loads = 0;
  await handleChatRequest(request("Comment vas-tu ?"), {uid: "test-uid"}, {
    loadShoppingItems: async () => {
      loads++;
      return [];
    },
    generateResponse: async () => response("Je vais bien."),
  });
  assert.equal(loads, 0);
});

// eslint-disable-next-line max-len
test("answers a confirmed marriage date directly from canonical Human", async () => {
  const value = request("Quelle est ma date de mariage");
  value.conversationContext.sections = [{
    type: "human",
    availability: "available",
    freshness: "current",
    items: [{
      type: "spouse",
      confirmation: "confirmed",
      freshness: "current",
      facts: {
        kind: "partner",
        marriageDate: "2020-08-12",
      },
    }],
    budgetLimit: 40,
    budgetUsed: 2,
    omittedCount: 0,
    truncated: false,
  }];
  value.conversationContext.budgetUsed = 2;
  let generations = 0;

  const result = await handleChatRequest(value, {uid: "test-uid"}, {
    generateResponse: async () => {
      generations++;
      return response("unexpected");
    },
  });

  assert.equal(generations, 0);
  assert.equal(result.reply, "Ta date de mariage est le 12 août 2020.");
  assert.equal(result.epistemic.responseKind, "answer");
  assert.equal(
      result.epistemic.groundingReferences[0].factKey,
      "marriageDate",
  );
});

// eslint-disable-next-line max-len
test("recognizes natural variants without intercepting a statement", async () => {
  const known = request("Quand est-ce que je me suis mariée ?");
  known.conversationContext.sections = [{
    type: "human",
    availability: "available",
    freshness: "current",
    items: [{
      type: "spouse",
      confirmation: "confirmed",
      freshness: "current",
      facts: {marriageDate: "2021-05-04"},
    }],
    budgetLimit: 40,
    budgetUsed: 1,
    omittedCount: 0,
    truncated: false,
  }];
  known.conversationContext.budgetUsed = 1;
  const direct = await handleChatRequest(known, {uid: "test-uid"});
  assert.equal(direct.reply, "Ta date de mariage est le 4 mai 2021.");

  let generations = 0;
  const statement = request("Ma date de mariage est le 4 mai 2021");
  const generated = await handleChatRequest(statement, {uid: "test-uid"}, {
    generateResponse: async () => {
      generations++;
      return response("Je peux retenir cette information.");
    },
  });
  assert.equal(generations, 1);
  assert.equal(generated.reply, "Je peux retenir cette information.");
});

test("answers confirmed personal and family profile facts", async () => {
  for (const [message, expected] of [
    ["Comment je m’appelle ?", "Tu t’appelles Sophia."],
    ["C’est quoi mon prénom ?", "Tu t’appelles Sophia."],
    ["Quelle est ma date de naissance ?", "Tu es née le 2 février 1990."],
    ["Rappelle-moi ma date de naissance", "Tu es née le 2 février 1990."],
    ["Quand est mon anniversaire ?", "Tu es née le 2 février 1990."],
    ["Comment s’appelle mon mari ?", "Ton mari s’appelle Willy."],
    [
      "Comment s’appelle mon conjoint ?",
      "La personne qui partage ta vie s’appelle Willy.",
    ],
    [
      "Quelle est la date de naissance de mon fils ?",
      "Pour Kassim, c’est le 10 avril 2022.",
    ],
    ["Quand est né Kassim ?", "Pour Kassim, c’est le 10 avril 2022."],
    [
      "Quand est l’anniversaire de Kassim ?",
      "Pour Kassim, c’est le 10 avril 2022.",
    ],
  ]) {
    let generations = 0;
    const result = await handleChatRequest(
        personalProfileRequest(message),
        {uid: "test-uid"},
        {generateResponse: async () => {
          generations++;
          return response("unexpected");
        }},
    );

    assert.equal(generations, 0, message);
    assert.equal(result.reply, expected, message);
  }
});

test("keeps a short reply inside its guided discussion", async () => {
  const value = personalProfileRequest(
      "Contexte de la discussion choisie par l’utilisatrice : " +
      "L’anniversaire de Willy est le 22 octobre. Première étape utile : " +
      "quel type d’anniversaire Willy aimerait-il ?\n" +
      "Nouveau message de l’utilisatrice : resto",
  );
  value.autonomyMode = "paused";
  value.conversationMode = "guidedDiscussion";
  value.allowedStructuredResponseKinds = [
    "answer", "answerWithCaveat", "clarificationRequired",
    "cannotDetermine", "contextUnavailable", "unsupportedRequest",
    "safeFailure",
  ];
  let generations = 0;

  const result = await handleChatRequest(value, {uid: "test-uid"}, {
    generateResponse: async ({systemContent}) => {
      generations++;
      assert.match(systemContent, /guidedDiscussion/);
      return response(
          "D’accord, partons sur un restaurant. " +
          "Tu veux que je t’aide à en trouver un ?",
      );
    },
  });

  assert.equal(generations, 1);
  assert.equal(
      result.reply,
      "D’accord, partons sur un restaurant. " +
      "Tu veux que je t’aide à en trouver un ?",
  );
  assert.doesNotMatch(result.reply, /22 octobre 1991/);
});

test("keeps a short ordinary reply in its bounded conversation", async () => {
  const value = personalProfileRequest("resto");
  value.conversationMode = "contextualFollowUp";
  value.conversationHistory = [
    {role: "assistant", text: "Quel type de sortie aimerais-tu pour Willy ?"},
  ];
  let generations = 0;

  const result = await handleChatRequest(value, {uid: "test-uid"}, {
    generateResponse: async ({systemContent}) => {
      generations++;
      assert.match(systemContent, /contextualFollowUp/);
      assert.match(systemContent, /Quel type de sortie aimerais-tu/);
      return response("D’accord, partons sur un restaurant.");
    },
  });

  assert.equal(generations, 1);
  assert.equal(result.reply, "D’accord, partons sur un restaurant.");
  assert.doesNotMatch(result.reply, /22 octobre 1991/);
});

test("does not treat a personal statement as a profile question", async () => {
  let generations = 0;
  const value = personalProfileRequest("Je m’appelle Sophia");
  const result = await handleChatRequest(value, {uid: "test-uid"}, {
    generateResponse: async () => {
      generations++;
      return response("Je le sais maintenant.");
    },
  });

  assert.equal(generations, 1);
  assert.equal(result.reply, "Je le sais maintenant.");
});

test("does not choose between several children without a name", async () => {
  const value = personalProfileRequest(
      "Quelle est la date de naissance de mon enfant ?",
  );
  value.conversationContext.sections[0].items.push({
    type: "person",
    confirmation: "confirmed",
    freshness: "current",
    facts: {
      nodeId: "human:person:person-emma",
      personRole: "related",
      displayName: "Emma",
      birthDate: "2018-06-05",
    },
  });
  value.conversationContext.sections[1].items.push({
    type: "relation",
    confirmation: "confirmed",
    freshness: "current",
    facts: {
      relationRole: "child",
      sourceNodeId: "human:person:person-main",
      targetNodeId: "human:person:person-emma",
    },
  });
  value.conversationContext.sections[0].budgetUsed = 16;
  value.conversationContext.sections[1].budgetUsed = 9;
  value.conversationContext.budgetUsed = 25;
  let generations = 0;

  const result = await handleChatRequest(value, {uid: "test-uid"}, {
    generateResponse: async () => {
      generations++;
      return response("De quel enfant parles-tu ?");
    },
  });

  assert.equal(generations, 1);
  assert.equal(result.reply, "De quel enfant parles-tu ?");
});

test("answers grounded profile schedules", async () => {
  for (const [message, expected] of [
    [
      "Quels sont mes horaires de travail ?",
      "Tu travailles le lundi de 9 h à 12 h et le mercredi de 14 h à 17 h.",
    ],
    [
      "À quelle heure je commence le travail ?",
      "Tu travailles le lundi de 9 h à 12 h et le mercredi de 14 h à 17 h.",
    ],
    [
      "Quels sont les horaires de travail de Willy ?",
      "Willy travaille le mardi de 8 h à 16 h.",
    ],
    [
      "Quand travaille Willy ?",
      "Willy travaille le mardi de 8 h à 16 h.",
    ],
    [
      "Quelles sont mes activités ?",
      "Tes activités sont : Pilate le lundi de 18 h à 19 h et Natation " +
        "le mercredi de 10 h à 11 h.",
    ],
    [
      "Quand est mon Pilates ?",
      "Tu as Pilate le lundi de 18 h à 19 h.",
    ],
    [
      "Quels sont les horaires d’école de Kassim ?",
      "Kassim va à l’école le lundi et le mardi de 8 h 30 à 16 h 30.",
    ],
    [
      "Quelles sont les activités de Kassim ?",
      "Les activités de Kassim sont : Football le mercredi de 17 h à 18 h.",
    ],
  ]) {
    let generations = 0;
    const result = await handleChatRequest(
        scheduledProfileRequest(message),
        {uid: "test-uid"},
        {generateResponse: async () => {
          generations++;
          return response("unexpected");
        }},
    );

    assert.equal(generations, 0, message);
    assert.equal(result.reply, expected, message);
    assert.equal(result.epistemic.responseKind, "answer", message);
    assert.ok(
        result.epistemic.usedSourceTypes.includes("lifeContextRoutine"),
        message,
    );
  }
});

test("does not guess ambiguous child schedules", async () => {
  const value = scheduledProfileRequest(
      "Quels sont les horaires d’école de mon enfant ?");
  value.conversationContext.sections[0].items.push({
    type: "person",
    confirmation: "confirmed",
    freshness: "current",
    facts: {
      nodeId: "human:person:person-emma",
      personRole: "related",
      displayName: "Emma",
      birthDate: "2018-06-05",
    },
  });
  value.conversationContext.sections[1].items.push({
    type: "relation",
    confirmation: "confirmed",
    freshness: "current",
    facts: {
      relationRole: "child",
      sourceNodeId: "human:person:person-main",
      targetNodeId: "human:person:person-emma",
    },
  });
  let generations = 0;
  const result = await handleChatRequest(value, {uid: "test-uid"}, {
    generateResponse: async () => {
      generations++;
      return response("De quel enfant parles-tu ?");
    },
  });

  assert.equal(generations, 1);
  assert.equal(result.reply, "De quel enfant parles-tu ?");
});

test("does not intercept a profile schedule statement", async () => {
  let generations = 0;
  const value = scheduledProfileRequest(
      "Je travaille le lundi de 9 heures à 12 heures");
  const result = await handleChatRequest(value, {uid: "test-uid"}, {
    generateResponse: async () => {
      generations++;
      return response("C’est bien noté.");
    },
  });

  assert.equal(generations, 1);
  assert.equal(result.reply, "C’est bien noté.");
});

test(
    "does not present a truncated schedule as the complete profile",
    async () => {
      const value = scheduledProfileRequest("Quelles sont mes activités ?");
      const routineSection = value.conversationContext.sections[2];
      routineSection.truncated = true;
      routineSection.omittedCount = 2;
      value.conversationContext.omittedCount = 2;
      value.conversationContext.truncatedSections = ["routine"];
      let generations = 0;
      const result = await handleChatRequest(value, {uid: "test-uid"}, {
        generateResponse: async () => {
          generations++;
          return response(
              "Je n’ai pas encore toute la liste de tes activités.",
          );
        },
      });

      assert.equal(generations, 1);
      assert.equal(
          result.reply,
          "Je n’ai pas encore toute la liste de tes activités.",
      );
    },
);

test("answers family/work status from canonical Human", async () => {
  for (const [message, factKey, value, expected] of [
    [
      "Quelle est ma situation familiale ?",
      "familyStatus",
      "Nous sommes une famille avec enfants",
      "Tu vis en famille avec tes enfants.",
    ],
    [
      "Quel est mon statut professionnel ?",
      "workStatus",
      "Je suis à la maison",
      "Tu es actuellement au foyer.",
    ],
    [
      "Quelle est ma profession ?",
      "workStatus",
      "Je suis salariée",
      "Tu es salariée.",
    ],
    [
      "Quelle est ma situation familiale ?",
      "familyStatus",
      "Je vis seule",
      "Tu vis seule.",
    ],
    [
      "Quelle est ma situation familiale ?",
      "familyStatus",
      "Nous sommes une famille monoparentale",
      "Tu vis seule avec tes enfants.",
    ],
    [
      "Quelle est ma situation familiale ?",
      "familyStatus",
      "Je vis en couple",
      "Tu vis en couple.",
    ],
    [
      "Quelle est ma situation professionnelle ?",
      "workStatus",
      "Je ne travaille pas actuellement",
      "Tu ne travailles pas actuellement.",
    ],
    [
      "Quelle est ma situation professionnelle ?",
      "workStatus",
      "Je suis entrepreneuse",
      "Tu es entrepreneuse.",
    ],
    [
      "Quelle est ma situation professionnelle ?",
      "workStatus",
      "Je suis étudiante",
      "Tu es étudiante.",
    ],
  ]) {
    const valueRequest = request(message);
    valueRequest.conversationContext.sections = [{
      type: "human",
      availability: "available",
      freshness: "current",
      items: [{
        type: "person",
        confirmation: "confirmed",
        freshness: "current",
        facts: {[factKey]: value},
      }],
      budgetLimit: 55,
      budgetUsed: 1,
      omittedCount: 0,
      truncated: false,
    }];
    valueRequest.conversationContext.budgetUsed = 1;
    let generations = 0;

    const result = await handleChatRequest(
        valueRequest,
        {uid: "test-uid"},
        {generateResponse: async () => {
          generations++;
          return response("unexpected");
        }},
    );

    assert.equal(generations, 0, message);
    assert.equal(result.reply, expected, message);
    assert.equal(
        result.epistemic.groundingReferences[0].factKey,
        factKey,
        message,
    );
  }
});

test("personalizes family status from confirmed relations", async () => {
  const valueRequest = request("Quelle est ma situation familiale ?");
  valueRequest.conversationContext.sections = [
    {
      type: "human",
      availability: "available",
      freshness: "current",
      items: [
        {
          type: "person",
          confirmation: "confirmed",
          freshness: "current",
          facts: {
            nodeId: "human:person:person-main",
            familyStatus: "Nous sommes une famille avec enfants",
          },
        },
        {
          type: "person",
          confirmation: "confirmed",
          freshness: "current",
          facts: {
            nodeId: "human:person:person-willy",
            displayName: "Willy",
          },
        },
        {
          type: "person",
          confirmation: "confirmed",
          freshness: "current",
          facts: {
            nodeId: "human:person:person-kassim",
            displayName: "Kassim",
          },
        },
      ],
      budgetLimit: 55,
      budgetUsed: 7,
      omittedCount: 0,
      truncated: false,
    },
    {
      type: "relation",
      availability: "available",
      freshness: "current",
      items: [
        {
          type: "relation",
          confirmation: "confirmed",
          freshness: "current",
          facts: {
            relationRole: "spouse",
            sourceNodeId: "human:person:person-main",
            targetNodeId: "human:person:person-willy",
          },
        },
        {
          type: "relation",
          confirmation: "confirmed",
          freshness: "current",
          facts: {
            relationRole: "child",
            sourceNodeId: "human:person:person-main",
            targetNodeId: "human:person:person-kassim",
          },
        },
      ],
      budgetLimit: 50,
      budgetUsed: 6,
      omittedCount: 0,
      truncated: false,
    },
  ];
  valueRequest.conversationContext.budgetUsed = 13;

  const result = await handleChatRequest(valueRequest, {uid: "test-uid"});

  assert.equal(result.reply, "Tu vis en famille avec Willy et Kassim.");
  assert.deepEqual(
      result.epistemic.usedSourceTypes,
      ["lifeContextHuman", "lifeContextRelation"],
  );
  assert.deepEqual(
      result.epistemic.personalClaims[0].sourceReferenceIndexes,
      [0, 1, 2],
  );
});

test("returns task clarification before model generation", async () => {
  let generations = 0;
  const result = await handleChatRequest(
      request("Crée une tâche prioritaire pour demain."),
      {uid: "test-uid"},
      {
        now: () => new Date("2026-07-27T10:00:00.000Z"),
        generateResponse: async () => {
          generations++;
          return response("unexpected");
        },
      },
  );

  assert.equal(generations, 0);
  assert.equal(result.reply, "Quelle tâche veux-tu créer ?");
  assert.deepEqual(result.actions, []);
  assert.deepEqual(result.memories, []);
  assert.equal(result.epistemic.responseKind, "clarificationRequired");
  assert.deepEqual(
      result.epistemic.clarification.missingFieldCodes,
      ["missingTaskTarget"],
  );
  assert.equal(result.epistemic.clarification.maximumAttempts, 3);
});

test("critical NLU ambiguity clarifies without calling the model", async () => {
  for (const message of [
    "Je veux plus de bananes",
    "Ne crée pas de tâche",
    "Annule pas le rendez-vous",
    "Achète du lait et décale le rendez-vous",
  ]) {
    let generations = 0;
    const result = await handleChatRequest(
        request(message),
        {uid: "test-uid"},
        {
          now: () => new Date("2026-07-27T10:00:00.000Z"),
          generateResponse: async () => {
            generations++;
            return response("unexpected", [{type: "shopping", title: "Lait"}]);
          },
        },
    );

    assert.equal(generations, 0, message);
    assert.deepEqual(result.actions, [], message);
    assert.deepEqual(result.memories, [], message);
    assert.equal(
        result.epistemic.responseKind,
        "clarificationRequired",
        message,
    );
    assert.equal(result.epistemic.clarification.maximumAttempts, 3, message);
    assert.equal(
        result.epistemic.clarification.expiresAt,
        "2026-07-27T10:10:00.000Z",
        message,
    );
  }
});

test("returns a structured non-executable Event draft", async () => {
  let generations = 0;
  const result = await handleChatRequest(
      request("medecin demain 15h"),
      {uid: "test-uid"},
      {
        now: () => new Date("2026-07-29T12:00:00.000Z"),
        generateResponse: async () => {
          generations++;
          return response("unexpected");
        },
      },
  );

  assert.equal(generations, 0);
  assert.deepEqual(result.actions, []);
  assert.equal(result.epistemic.responseKind, "clarificationRequired");
  assert.deepEqual(result.epistemic.clarification.draft, {
    schemaVersion: 1,
    draftType: "eventCreation",
    logicalRequestId: "0123456789abcdef0123456789abcdef",
    draftId: "event-draft-0123456789abcdef0123456789abcdef",
    title: "Consultation médecin",
    date: "2026-07-30",
    startTime: "15:00",
    durationMinutes: null,
    travelGoMinutes: null,
    travelBackMinutes: null,
    marginMinutes: null,
    expectedField: "duration",
    createdAt: "2026-07-29T12:00:00.000Z",
    expiresAt: "2026-07-29T12:15:00.000Z",
    sessionGeneration: 0,
  });
});

test("handles the canonical bounded payload without mutating it", async () => {
  const original = structuredClone(payload);
  const calls = [];

  const result = await handleChatRequest(payload, {uid: "test-uid"}, {
    apiKey: "test-key",
    now: () => new Date("2026-07-20T10:00:00.000Z"),
    env: {ZELIA_MODEL_FAST: "test-fast"},
    logger: {info() {}},
    generateResponse: async (request) => {
      calls.push(request);
      return response("C'est noté.", [{type: "shopping", title: "Lait"}]);
    },
  });

  assert.deepEqual(payload, original);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].apiKey, "test-key");
  assert.equal(calls[0].userMessage, payload.message);
  assert.equal(calls[0].model, "test-fast");
  assert.equal(calls[0].tier, "fast");
  assert.equal(calls[0].reasoningEffort, "none");
  assert.equal(
      calls[0].correlationId,
      "0123456789abcdef0123456789abcdef",
  );
  assert.ok(calls[0].signal instanceof AbortSignal);
  assert.deepEqual(result, {
    reply: "C'est noté.",
    actions: [{type: "shopping", title: "Lait"}],
    memories: [],
    epistemic: response("x", [{type: "shopping", title: "Lait"}]).epistemic,
  });
});

test("rejects missing canonical fields", async () => {
  await assert.rejects(
      () => handleChatRequest({}, {uid: "test-uid"}),
      /conversation_request_invalid/,
  );
});

test(
    "keeps only a participant literally present in the user message",
    async () => {
      const explicit = await handleChatRequest(
          request(
              "Ajoute un rendez-vous avec Person A demain à 10h pendant 30 min",
          ),
          {uid: "test-uid"}, {
            now: () => new Date("2026-07-20T10:00:00.000Z"),
            logger: {info() {}},
            generateResponse: async () => response("D'accord", [{
              type: "event",
              title: "Rendez-vous",
              date: "2026-07-25",
              time: "10:00",
              durationMinutes: 30,
              participant: {
                label: "Person A",
                entityType: "person",
                evidence: "explicit_user_input",
              },
            }]),
          });
      assert.equal(explicit.actions[0].participant.label, "Person A");

      const invented = await handleChatRequest(
          request("Ajoute un rendez-vous demain à 10h pendant 30 min"),
          {uid: "test-uid"},
          {
            now: () => new Date("2026-07-20T10:00:00.000Z"),
            logger: {info() {}},
            generateResponse: async () => response("D'accord", [{
              type: "event",
              title: "Rendez-vous",
              date: "2026-07-25",
              time: "10:00",
              durationMinutes: 30,
              participant: {
                label: "Person A",
                entityType: "person",
                evidence: "explicit_user_input",
              },
            }]),
          },
      );
      assert.equal("participant" in invented.actions[0], false);
    },
);

test(
    "aborts and rejects the whole OpenAI operation at its deadline",
    async () => {
      let receivedSignal;

      await assert.rejects(
          () => runWithOpenAiDeadline((signal) => {
            receivedSignal = signal;
            return new Promise(() => {});
          }, 5),
          /OPENAI_TIMEOUT/,
      );

      assert.equal(receivedSignal.aborted, true);
    },
);

test("logs a bounded timeout diagnostic without request content", async () => {
  const logs = [];
  await assert.rejects(
      () => handleChatRequest(
          request("PRIVATE USER MESSAGE"),
          {uid: "test-uid"},
          {
            now: () => new Date("2026-07-20T10:00:00.000Z"),
            openAiTimeoutMs: 5,
            logger: {
              info: (...values) => logs.push(values),
              error: (...values) => logs.push(values),
            },
            generateResponse: async () => new Promise(() => {}),
          },
      ),
      /OPENAI_TIMEOUT/,
  );

  const timeoutLog = logs.find((line) =>
    line[0] === "ZELIA_OPENAI_TIMEOUT");
  assert.ok(timeoutLog);
  assert.equal(timeoutLog[1].code, "timeout");
  assert.equal(timeoutLog[1].model, "gpt-5.6-terra");
  assert.equal(timeoutLog[1].reasoningEffort, "low");
  assert.equal(
      timeoutLog[1].correlationId,
      "0123456789abcdef0123456789abcdef",
  );
  assert.ok(timeoutLog[1].durationMs >= 0);
  assert.equal(JSON.stringify(logs).includes("PRIVATE USER MESSAGE"), false);
});

test(
    "uses one deadline and cleans it after real fallback success",
    async () => {
      const scheduled = [];
      const cleared = [];
      const timers = {
        setTimeout(callback, timeoutMs) {
          const token = {callback, timeoutMs};
          scheduled.push(token);
          return token;
        },
        clearTimeout(token) {
          cleared.push(token);
        },
      };
      const attempts = [];
      const client = {
        responses: {
          async create(request, options) {
            attempts.push({request, signal: options.signal});
            if (attempts.length === 1) {
              const error = new Error("Service unavailable");
              error.status = 503;
              throw error;
            }
            return {
              output_text: JSON.stringify(response("Réponse de secours")),
            };
          },
        },
      };

      const result = await runWithOpenAiDeadline(
          (signal) => generateZeliaResponse({
            apiKey: "test-key",
            systemContent: "SYSTEM",
            userMessage: "USER",
            model: "gpt-5.6-terra",
            client,
            signal,
          }),
          OPENAI_TIMEOUT_MS,
          timers,
      );

      assert.equal(result.visibleText, "Réponse de secours");
      assert.equal(scheduled.length, 1);
      assert.equal(scheduled[0].timeoutMs, OPENAI_TIMEOUT_MS);
      assert.equal(cleared.length, 1);
      assert.equal(cleared[0], scheduled[0]);
      assert.ok(attempts[0].signal instanceof AbortSignal);
      assert.equal(attempts[1].signal, attempts[0].signal);
    },
);

test("cleans the single deadline after real OpenAI failure", async () => {
  const scheduled = [];
  const cleared = [];
  const timers = {
    setTimeout(callback, timeoutMs) {
      const token = {callback, timeoutMs};
      scheduled.push(token);
      return token;
    },
    clearTimeout(token) {
      cleared.push(token);
    },
  };
  const client = {
    responses: {
      async create() {
        const error = new Error("Invalid request");
        error.status = 400;
        throw error;
      },
    },
  };

  await assert.rejects(
      () => runWithOpenAiDeadline(
          (signal) => generateZeliaResponse({
            apiKey: "test-key",
            systemContent: "SYSTEM",
            userMessage: "USER",
            model: "gpt-5.6-terra",
            client,
            signal,
          }),
          OPENAI_TIMEOUT_MS,
          timers,
      ),
      /Invalid request/,
  );

  assert.equal(scheduled.length, 1);
  assert.equal(cleared.length, 1);
  assert.equal(cleared[0], scheduled[0]);
});
