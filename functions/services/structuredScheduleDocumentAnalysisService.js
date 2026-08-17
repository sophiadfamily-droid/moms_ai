const crypto = require("node:crypto");
const {OpenAI} = require("openai");

const {
  structuredScheduleExtractionJsonSchema,
} = require("../brain/structuredScheduleExtractionJsonSchema");
const {
  OPENAI_TIMEOUT_MS,
  runWithOpenAiDeadline,
} = require("./chatRequestHandler");

const SCHEDULE_ANALYSIS_MODEL = "gpt-4.1-mini";
const SCHEDULE_ANALYSIS_SCHEMA_NAME = "structured_schedule_extraction";

/**
 * Builds a stateless OpenAI request for schedule extraction.
 *
 * @param {Object} params Request parameters.
 * @param {string} params.documentKind Document kind.
 * @param {string} params.mimeType Validated MIME type.
 * @param {string} params.fileBase64 Validated base64 document.
 * @return {Object} OpenAI Responses API request.
 */
function buildScheduleAnalysisRequest({documentKind, mimeType, fileBase64}) {
  const documentContent = documentKind === "pdf" ? {
    type: "input_file",
    filename: "planning.pdf",
    file_data: `data:application/pdf;base64,${fileBase64}`,
  } : {
    type: "input_image",
    image_url: `data:${mimeType};base64,${fileBase64}`,
    detail: "high",
  };

  return {
    model: SCHEDULE_ANALYSIS_MODEL,
    store: false,
    temperature: 0,
    max_output_tokens: 5000,
    instructions: [
      "Tu extrais uniquement des éléments de planning visibles.",
      "Une ligne peut être un rendez-vous daté ou un horaire hebdomadaire.",
      "N'invente jamais une date, un jour, une heure, un lieu ou une personne.",
      "Utilise lundi=1 jusqu'à dimanche=7.",
      "Utilise HH:mm sur 24 heures et YYYY-MM-DD.",
      "Pour un service de nuit, relie le début du soir à la fin visible le",
      "lendemain. Une fin plus matinale que le début signifie le lendemain",
      "et n'est pas une incertitude si les deux horaires sont lisibles.",
      "Si une valeur manque ou est illisible, renvoie null ou [] et ajoute",
      "l'incertitude correspondante. Le titre doit rester court et fidèle.",
      "N'explique rien et ne reproduis pas le texte brut du document.",
    ].join(" "),
    input: [{
      role: "user",
      content: [
        documentContent,
        {
          type: "input_text",
          text: "Extrais toutes les plages horaires dans le schéma demandé.",
        },
      ],
    }],
    text: {
      format: {
        type: "json_schema",
        name: SCHEDULE_ANALYSIS_SCHEMA_NAME,
        strict: true,
        schema: structuredScheduleExtractionJsonSchema,
      },
    },
  };
}

/**
 * Converts the strict provider response into the client review contract.
 *
 * @param {Object} response OpenAI Responses API result.
 * @param {Object} subject Local subject context.
 * @return {Object} Structured schedule import result.
 */
function parseScheduleAnalysisResponse(response, subject) {
  const output = response && typeof response.output_text === "string" ?
    response.output_text.trim() : "";
  if (!output) throw new Error("SCHEDULE_ANALYSIS_EMPTY_OUTPUT");

  let parsed;
  try {
    parsed = JSON.parse(output);
  } catch (error) {
    throw new Error("SCHEDULE_ANALYSIS_INVALID_JSON", {cause: error});
  }
  if (!parsed || !Array.isArray(parsed.proposals) ||
      parsed.proposals.length > 100) {
    throw new Error("SCHEDULE_ANALYSIS_INVALID_CONTRACT");
  }

  const proposals = mergeOvernightScheduleRows(parsed.proposals);
  return {
    schemaVersion: 1,
    importId: crypto.randomUUID(),
    proposals: proposals.map((proposal, index) => ({
      schemaVersion: 1,
      proposalId: `${index + 1}-${crypto.randomUUID()}`,
      ...proposal,
      subjectEntityId: subject.entityId,
      subjectLabel: subject.label,
      state: "pendingReview",
    })),
  };
}

/**
 * Rejoins a night shift split by a monthly calendar across two civil days.
 * The provider can read the evening start on one cell and the morning end on
 * the following cell as two incomplete rows. This deterministic pass merges
 * only an unambiguous evening-to-next-morning pair.
 *
 * @param {Array<Object>} source Extracted proposals.
 * @return {Array<Object>} Proposals with safe overnight pairs joined.
 */
function mergeOvernightScheduleRows(source) {
  const removed = new Set();
  const result = source.map((proposal, index) => {
    if (removed.has(index) || !isOvernightStart(proposal)) return proposal;
    const candidates = [];
    for (let nextIndex = 0; nextIndex < source.length; nextIndex += 1) {
      if (nextIndex === index || removed.has(nextIndex)) continue;
      const next = source[nextIndex];
      if (isMatchingOvernightEnd(proposal, next)) {
        candidates.push({next, nextIndex});
      }
    }
    if (candidates.length !== 1) return proposal;

    const {next, nextIndex} = candidates[0];
    removed.add(nextIndex);
    const uncertainties = [...new Set([
      ...(proposal.uncertainties || []),
      ...(next.uncertainties || []),
    ])].filter((value) => value !== "endTime" && value !== "startTime");
    return {
      ...proposal,
      endTime: next.endTime,
      place: proposal.place || next.place || null,
      confidence: uncertainties.length === 0 ? "high" : "medium",
      uncertainties,
    };
  });
  return result.filter((_proposal, index) => !removed.has(index));
}

/**
 * @param {Object} proposal Extracted row.
 * @return {boolean} Whether this row is a possible night-shift start.
 */
function isOvernightStart(proposal) {
  return proposal && proposal.temporalKind === "dated" &&
    typeof proposal.dateIso === "string" &&
    clockMinutes(proposal.startTime) >= 18 * 60 &&
    proposal.endTime === null;
}

/**
 * @param {Object} start Possible night-shift start.
 * @param {Object} end Possible following-day end.
 * @return {boolean} Whether end safely completes start on the next day.
 */
function isMatchingOvernightEnd(start, end) {
  const endMinutes = clockMinutes(end && end.endTime);
  return end && end.temporalKind === "dated" &&
    end.target === start.target &&
    normalizedLabel(end.title) === normalizedLabel(start.title) &&
    end.dateIso === nextDateIso(start.dateIso) &&
    end.startTime === null &&
    endMinutes >= 0 && endMinutes <= 12 * 60 &&
    compatiblePlaces(start.place, end.place);
}

/**
 * @param {*} value Possible local clock.
 * @return {number} Minutes since midnight, or -1 for an invalid clock.
 */
function clockMinutes(value) {
  if (typeof value !== "string" || !/^\d{2}:\d{2}$/.test(value)) return -1;
  const [hour, minute] = value.split(":").map(Number);
  return hour * 60 + minute;
}

/**
 * @param {*} value Possible label.
 * @return {string} A bounded comparison label.
 */
function normalizedLabel(value) {
  return typeof value === "string" ? value.trim().toLocaleLowerCase("fr") : "";
}

/**
 * @param {*} first First optional place.
 * @param {*} second Second optional place.
 * @return {boolean} Whether two optional places can belong to one shift.
 */
function compatiblePlaces(first, second) {
  return !first || !second ||
    normalizedLabel(first) === normalizedLabel(second);
}

/**
 * @param {*} value Possible ISO civil date.
 * @return {string} The following ISO civil date, or empty when invalid.
 */
function nextDateIso(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value || "");
  if (!match) return "";
  const date = new Date(Date.UTC(
      Number(match[1]), Number(match[2]) - 1, Number(match[3]) + 1,
  ));
  return date.toISOString().slice(0, 10);
}

/**
 * Analyzes a validated planning image or PDF without retaining it.
 *
 * @param {Object} params Analysis parameters.
 * @return {Promise<Object>} Structured schedule import result.
 */
async function analyzeStructuredScheduleDocument({
  apiKey,
  documentKind,
  mimeType,
  fileBase64,
  subject,
  client = null,
  signal,
}) {
  const openai = client || new OpenAI({apiKey});
  const request = buildScheduleAnalysisRequest({
    documentKind, mimeType, fileBase64,
  });
  const response = signal ?
    await openai.responses.create(request, {signal}) :
    await runWithOpenAiDeadline(
        (deadlineSignal) => openai.responses.create(
            request,
            {signal: deadlineSignal},
        ),
        OPENAI_TIMEOUT_MS,
    );
  return parseScheduleAnalysisResponse(response, subject);
}

module.exports = {
  SCHEDULE_ANALYSIS_MODEL,
  SCHEDULE_ANALYSIS_SCHEMA_NAME,
  analyzeStructuredScheduleDocument,
  buildScheduleAnalysisRequest,
  mergeOvernightScheduleRows,
  parseScheduleAnalysisResponse,
};
