/* eslint-disable require-jsdoc */
const assert = require("node:assert/strict");
const test = require("node:test");

const {
  SCHEDULE_ANALYSIS_MODEL,
  analyzeStructuredScheduleDocument,
  buildScheduleAnalysisRequest,
  mergeOvernightScheduleRows,
  parseScheduleAnalysisResponse,
} = require("../../services/structuredScheduleDocumentAnalysisService");

function proposal() {
  return {
    target: "schoolSchedule",
    temporalKind: "recurringWeekly",
    title: "École",
    dateIso: null,
    weekdays: [1, 2, 4, 5],
    startTime: "08:30",
    endTime: "16:30",
    place: null,
    confidence: "high",
    uncertainties: [],
  };
}

test("builds a stateless high-detail image analysis request", () => {
  const request = buildScheduleAnalysisRequest({
    documentKind: "image",
    mimeType: "image/jpeg",
    fileBase64: "binary",
  });

  assert.equal(request.model, SCHEDULE_ANALYSIS_MODEL);
  assert.equal(request.store, false);
  assert.equal(request.input[0].content[0].type, "input_image");
  assert.equal(
      request.input[0].content[0].image_url,
      "data:image/jpeg;base64,binary",
  );
  assert.equal(request.input[0].content[0].detail, "high");
  assert.equal(request.text.format.strict, true);
  assert.equal(JSON.stringify(request).includes("subject"), false);
});

test("builds a base64 PDF input without storage", () => {
  const request = buildScheduleAnalysisRequest({
    documentKind: "pdf",
    mimeType: "application/pdf",
    fileBase64: "binary",
  });
  assert.deepEqual(request.input[0].content[0], {
    type: "input_file",
    filename: "planning.pdf",
    file_data: "data:application/pdf;base64,binary",
  });
});

test("uses only supported strict-schema keywords", () => {
  const request = buildScheduleAnalysisRequest({
    documentKind: "image",
    mimeType: "image/png",
    fileBase64: "binary",
  });
  const serializedSchema = JSON.stringify(request.text.format.schema);
  assert.equal(serializedSchema.includes("uniqueItems"), false);
});

test("injects the profile subject after extraction", () => {
  const result = parseScheduleAnalysisResponse({
    output_text: JSON.stringify({proposals: [proposal()]}),
  }, {entityId: "child-1", label: "Kassim"});

  assert.equal(result.schemaVersion, 1);
  assert.equal(result.proposals.length, 1);
  assert.equal(result.proposals[0].subjectEntityId, "child-1");
  assert.equal(result.proposals[0].subjectLabel, "Kassim");
  assert.equal(result.proposals[0].state, "pendingReview");
});

test("accepts a document with no schedule without inventing one", () => {
  const result = parseScheduleAnalysisResponse({
    output_text: JSON.stringify({proposals: []}),
  }, {entityId: "user-1", label: "Sophia"});
  assert.deepEqual(result.proposals, []);
});

test("joins an evening start with the visible end on the next day", () => {
  const rows = mergeOvernightScheduleRows([
    {
      ...proposal(),
      target: "workSchedule",
      temporalKind: "dated",
      title: "Travail",
      dateIso: "2026-08-13",
      weekdays: [],
      startTime: "21:00",
      endTime: null,
      confidence: "medium",
      uncertainties: ["endTime"],
    },
    {
      ...proposal(),
      target: "workSchedule",
      temporalKind: "dated",
      title: "Travail",
      dateIso: "2026-08-14",
      weekdays: [],
      startTime: null,
      endTime: "09:00",
      confidence: "medium",
      uncertainties: ["startTime"],
    },
  ]);

  assert.equal(rows.length, 1);
  assert.equal(rows[0].dateIso, "2026-08-13");
  assert.equal(rows[0].startTime, "21:00");
  assert.equal(rows[0].endTime, "09:00");
  assert.equal(rows[0].confidence, "high");
  assert.deepEqual(rows[0].uncertainties, []);
});

test("does not join unrelated or ambiguous rows", () => {
  const start = {
    ...proposal(),
    target: "workSchedule",
    temporalKind: "dated",
    title: "Travail",
    dateIso: "2026-08-13",
    weekdays: [],
    startTime: "21:00",
    endTime: null,
  };
  const rows = mergeOvernightScheduleRows([
    start,
    {...start, dateIso: "2026-08-14", startTime: null, endTime: "09:00"},
    {...start, dateIso: "2026-08-14", startTime: null, endTime: "08:30"},
  ]);

  assert.equal(rows.length, 3);
});

test("rejects malformed provider output", () => {
  assert.throws(
      () => parseScheduleAnalysisResponse(
          {output_text: "not-json"},
          {entityId: "user-1", label: "Sophia"},
      ),
      /SCHEDULE_ANALYSIS_INVALID_JSON/,
  );
});

test("bounds a provider analysis with an abort signal", async () => {
  let receivedSignal;
  const client = {
    responses: {
      create: async (_request, options) => {
        receivedSignal = options.signal;
        return {output_text: JSON.stringify({proposals: [proposal()]})};
      },
    },
  };

  const result = await analyzeStructuredScheduleDocument({
    apiKey: "server-secret",
    documentKind: "image",
    mimeType: "image/png",
    fileBase64: "binary",
    subject: {entityId: "user-1", label: "Sophia"},
    client,
  });

  assert.equal(receivedSignal instanceof AbortSignal, true);
  assert.equal(result.proposals.length, 1);
});
