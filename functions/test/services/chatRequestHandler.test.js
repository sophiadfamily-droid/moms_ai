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

test("uses a 45 second total OpenAI deadline", () => {
  assert.equal(OPENAI_TIMEOUT_MS, 45000);
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
