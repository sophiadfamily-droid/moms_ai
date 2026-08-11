"use strict";
/* eslint-disable require-jsdoc */

const MONTHS = [
  "janvier", "février", "mars", "avril", "mai", "juin",
  "juillet", "août", "septembre", "octobre", "novembre", "décembre",
];

function normalizedText(value) {
  return value
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[’']/g, " ")
      .toLowerCase();
}

function requestedRelationshipDate(message) {
  const text = normalizedText(message);
  if (!asksQuestion(text)) return null;
  if (/\b(mariage|mariee?|maries?)\b/.test(text)) {
    return {
      factKey: "marriageDate",
      visiblePrefix: "Ta date de mariage est le",
      category: "relationshipFact",
      format: frenchDate,
      answer: (value) => `Ta date de mariage est le ${value}`,
    };
  }
  if (/\b(fiancailles|fiancee?|fiances?)\b/.test(text)) {
    return {
      factKey: "engagementDate",
      visiblePrefix: "Ta date de fiançailles est le",
      category: "relationshipFact",
      format: frenchDate,
      answer: (value) => `Ta date de fiançailles est le ${value}`,
    };
  }
  return null;
}

function asksQuestion(text) {
  return /\b(quel(?:le)?s?|quand|comment|connais|sais|rappelle|dis moi)\b/
      .test(text) ||
    text.includes("c est quoi");
}

function requestedPersonFact(message) {
  const text = normalizedText(message);
  if (!asksQuestion(text)) return null;

  let factKey = null;
  if (text.includes("date de naissance") || text.includes("anniversaire") ||
      /\bquand\b.*\bnaissance\b/.test(text) ||
      /\bquand\b.*\b(?:nee?|ne)\b/.test(text)) {
    factKey = "birthDate";
  } else if (/\bcomment\b.*\bappelle\b/.test(text) ||
      /\b(?:quel|quelle)\b.*\bprenom\b/.test(text) ||
      text.includes("c est quoi mon prenom")) {
    factKey = "displayName";
  }
  if (factKey === null) return null;

  let subject = "named";
  if (/\b(mon prenom|ma date de naissance|mon anniversaire|je m appelle)\b/
      .test(text) || /\bje suis nee?\b/.test(text)) {
    subject = "primary";
  } else if (/\b(mari|epoux|conjoint|partenaire|compagnon|femme|epouse)\b/
      .test(text) || /\b(conjointe|compagne)\b/.test(text)) {
    subject = "partner";
  } else if (/\b(fils|fille|enfant|enfants)\b/.test(text)) {
    subject = "child";
  }

  return {factKey, subject, text};
}

function currentPeopleAndRelations(context) {
  const people = [];
  const relations = [];
  for (const section of context.sections) {
    if (section.availability !== "available" ||
        section.freshness !== "current") {
      continue;
    }
    for (const item of section.items) {
      if (item.confirmation !== "confirmed" ||
          item.freshness !== "current") {
        continue;
      }
      if (section.type === "human" && item.type === "person") {
        people.push(item);
      }
      if (section.type === "relation" && item.type === "relation") {
        relations.push(item);
      }
    }
  }
  return {people, relations};
}

function relatedNodeIds(primaryNodeId, relations, role) {
  const result = new Set();
  for (const relation of relations) {
    const facts = relation.facts;
    if (role === "partner" &&
        ["partner", "spouse"].includes(facts.relationRole)) {
      if (facts.sourceNodeId === primaryNodeId) result.add(facts.targetNodeId);
      if (facts.targetNodeId === primaryNodeId) result.add(facts.sourceNodeId);
    }
    if (role === "child" && facts.relationRole === "child" &&
        facts.sourceNodeId === primaryNodeId) {
      result.add(facts.targetNodeId);
    }
  }
  return result;
}

function namedInMessage(name, normalizedMessage) {
  const normalizedName = normalizedText(name)
      .replace(/[^a-z0-9]+/g, " ")
      .trim();
  if (normalizedName.length === 0) return false;
  const searchable = ` ${normalizedMessage.replace(/[^a-z0-9]+/g, " ")} `;
  return searchable.includes(` ${normalizedName} `);
}

function routineWordKey(value) {
  if (value.length > 3 && /[sx]$/.test(value)) return value.slice(0, -1);
  return value;
}

function routineTitleInMessage(title, message) {
  const words = (value) => normalizedText(value)
      .replace(/[^a-z0-9]+/g, " ")
      .trim()
      .split(/\s+/)
      .filter((word) => word.length > 0)
      .map(routineWordKey);
  const titleWords = words(title);
  if (titleWords.length === 0) return false;
  const searchable = ` ${words(message).join(" ")} `;
  return searchable.includes(` ${titleWords.join(" ")} `);
}

function personFactSentence(requested, selected) {
  if (requested.factKey === "displayName") {
    const names = selected.map((person) => person.facts.displayName.trim());
    if (requested.subject === "primary") return `Tu t’appelles ${names[0]}`;
    if (requested.subject === "child" && names.length > 1) {
      return `Tes enfants s’appellent ${joinedNames(names)}`;
    }
    if (requested.subject === "child") {
      if (requested.text.includes("fils")) {
        return `Ton fils s’appelle ${names[0]}`;
      }
      if (requested.text.includes("fille")) {
        return `Ta fille s’appelle ${names[0]}`;
      }
      return `Ton enfant s’appelle ${names[0]}`;
    }
    if (requested.subject === "partner") {
      if (/\b(mari|epoux)\b/.test(requested.text)) {
        return `Ton mari s’appelle ${names[0]}`;
      }
      if (/\b(femme|epouse)\b/.test(requested.text)) {
        return `Ta femme s’appelle ${names[0]}`;
      }
      return `La personne qui partage ta vie s’appelle ${names[0]}`;
    }
    return null;
  }

  const value = frenchDate(selected[0].facts.birthDate);
  if (value === null) return null;
  if (requested.subject === "primary") return `Tu es née le ${value}`;
  const name = selected[0].facts.displayName;
  if (typeof name !== "string" || name.trim().length === 0) return null;
  return `Pour ${name.trim()}, c’est le ${value}`;
}

function canonicalPersonFactAnswer(request) {
  const requested = requestedPersonFact(request.message);
  if (requested === null) return null;
  const context = request.conversationContext;
  const {people, relations} = currentPeopleAndRelations(context);
  const primary = people.find((item) => item.facts.personRole === "primary");
  if (primary === undefined || typeof primary.facts.nodeId !== "string") {
    return null;
  }

  let selected = [];
  if (requested.subject === "primary") {
    selected = [primary];
  } else if (["partner", "child"].includes(requested.subject)) {
    const nodeIds = relatedNodeIds(
        primary.facts.nodeId,
        relations,
        requested.subject,
    );
    selected = people.filter((item) => nodeIds.has(item.facts.nodeId));
  } else {
    const connected = new Set([
      ...relatedNodeIds(primary.facts.nodeId, relations, "partner"),
      ...relatedNodeIds(primary.facts.nodeId, relations, "child"),
    ]);
    selected = people.filter((item) =>
      connected.has(item.facts.nodeId) &&
      typeof item.facts.displayName === "string" &&
      namedInMessage(item.facts.displayName, requested.text));
  }

  selected = selected.filter((item) => {
    const value = item.facts[requested.factKey];
    return typeof value === "string" && value.trim().length > 0 &&
      (requested.factKey !== "birthDate" || frenchDate(value) !== null);
  });
  if (selected.length === 0 ||
      requested.factKey === "birthDate" && selected.length !== 1) {
    return null;
  }

  const sentence = personFactSentence(requested, selected);
  if (sentence === null) return null;
  const related = requested.subject !== "primary";
  const groundingReferences = [
    {
      schemaVersion: 1,
      sourceType: "lifeContextHuman",
      section: "human",
      factKey: requested.factKey,
      freshness: "current",
      confirmation: "confirmed",
      projectionVersion: context.projectionVersion,
    },
    {
      schemaVersion: 1,
      sourceType: "lifeContextHuman",
      section: "human",
      factKey: "personRole",
      freshness: "current",
      confirmation: "confirmed",
      projectionVersion: context.projectionVersion,
    },
  ];
  if (related) {
    groundingReferences.push({
      schemaVersion: 1,
      sourceType: "lifeContextRelation",
      section: "relation",
      factKey: "relationRole",
      freshness: "current",
      confirmation: "confirmed",
      projectionVersion: context.projectionVersion,
    });
  }
  return {
    visibleText: `${sentence}.`,
    actions: [],
    memories: [],
    epistemic: {
      schemaVersion: 1,
      responseKind: "answer",
      epistemicState: "grounded",
      confidenceLevel: "high",
      usedSourceTypes: related ?
        ["lifeContextHuman", "lifeContextRelation"] : ["lifeContextHuman"],
      groundingReferences,
      personalClaims: [{
        claimId: `profile-person-${requested.factKey}`,
        category: "humanFact",
        sourceReferenceIndexes: groundingReferences.map((_, index) => index),
        certainty: "grounded",
      }],
      missingInformation: [],
      contradictions: [],
      clarification: null,
      uncertaintyCodes: [],
      contextStateObserved: context.state,
      warningCodes: [],
      responseId: `profile-person-${requested.factKey}-` +
        `${context.projectionVersion}`,
    },
  };
}

const DAY_NAMES = new Map([
  ["1", "lundi"], ["lundi", "lundi"], ["monday", "lundi"],
  ["2", "mardi"], ["mardi", "mardi"], ["tuesday", "mardi"],
  ["3", "mercredi"], ["mercredi", "mercredi"],
  ["wednesday", "mercredi"],
  ["4", "jeudi"], ["jeudi", "jeudi"], ["thursday", "jeudi"],
  ["5", "vendredi"], ["vendredi", "vendredi"],
  ["friday", "vendredi"],
  ["6", "samedi"], ["samedi", "samedi"], ["saturday", "samedi"],
  ["7", "dimanche"], ["dimanche", "dimanche"],
  ["sunday", "dimanche"],
]);
const DAY_POSITIONS = new Map([
  ["lundi", 1], ["mardi", 2], ["mercredi", 3], ["jeudi", 4],
  ["vendredi", 5], ["samedi", 6], ["dimanche", 7],
]);

function currentRoutineItems(context) {
  const items = [];
  let stale = false;
  let truncated = false;
  for (const section of context.sections) {
    if (section.type !== "routine" ||
        !["available", "availableStale"].includes(section.availability)) {
      continue;
    }
    stale = stale || section.freshness === "stale" ||
      section.availability === "availableStale";
    truncated = truncated || section.truncated;
    for (const item of section.items) {
      if (item.type !== "routine" || item.confirmation !== "confirmed" ||
          !["current", "stale"].includes(item.freshness)) {
        continue;
      }
      stale = stale || item.freshness === "stale";
      items.push(item);
    }
  }
  return {items, stale, truncated};
}

function requestedRoutineProfileFact(message, routines = []) {
  const text = normalizedText(message);
  if (!asksQuestion(text)) return null;
  const scheduleWords = new RegExp(
      "\\b(horaire|horaires|planning|jour|jours|heure|heures|quand|" +
      "commence|commencer|termine|terminer|finis|finir)\\b",
  );
  let kind = null;
  if (scheduleWords.test(text) &&
      /\b(travail\w*|boulot|professionnel|professionnelle)\b/.test(text)) {
    kind = "work";
  } else if (scheduleWords.test(text) &&
      /\b(ecole|creche|scolaire)\b/.test(text)) {
    kind = "school";
  } else if (/\b(activite|activites|sport|sports|loisir|loisirs)\b/
      .test(text)) {
    kind = "activity";
  }

  const namedTitles = routines.filter((item) =>
    typeof item.facts.title === "string" &&
    routineTitleInMessage(item.facts.title, text));
  if (kind === null && namedTitles.length === 0) return null;

  return {
    kind: kind || "named",
    text,
    namedTitles: new Set(namedTitles.map((item) => item.facts.title)),
    broadActivity: kind === "activity" &&
      /\b(quelles|quels|toutes|tous|liste)\b/.test(text),
  };
}

function relatedPeopleForRoutine(primary, people, relations, role) {
  const ids = relatedNodeIds(primary.facts.nodeId, relations, role);
  return people.filter((person) => ids.has(person.facts.nodeId));
}

function routineSubject(requested, people, relations) {
  const primary = people.find((item) => item.facts.personRole === "primary");
  if (primary === undefined || typeof primary.facts.nodeId !== "string") {
    return null;
  }
  const related = [
    ...relatedPeopleForRoutine(primary, people, relations, "partner"),
    ...relatedPeopleForRoutine(primary, people, relations, "child"),
  ];
  const named = related.filter((person) =>
    typeof person.facts.displayName === "string" &&
    namedInMessage(person.facts.displayName, requested.text));
  if (named.length === 1) return named[0];
  if (named.length > 1) return null;

  const asksChild = requested.kind === "school" ||
    /\b(fils|fille|enfant|enfants)\b/.test(requested.text);
  if (!asksChild) return primary;
  const children = relatedPeopleForRoutine(
      primary, people, relations, "child");
  return children.length === 1 ? children[0] : null;
}

function frenchClock(value) {
  if (typeof value !== "string") return null;
  const match = /^(\d{1,2})(?::|h)(\d{2})?$/.exec(value.trim());
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2] || "0");
  if (hour > 23 || minute > 59) return null;
  return minute === 0 ? `${hour} h` : `${hour} h ${match[2]}`;
}

function frenchDays(value) {
  if (typeof value !== "string") return null;
  const days = [];
  for (const raw of value.split(",")) {
    const day = DAY_NAMES.get(normalizedText(raw).trim());
    if (day !== undefined && !days.includes(day)) days.push(day);
  }
  if (days.length === 0) return null;
  days.sort((a, b) => DAY_POSITIONS.get(a) - DAY_POSITIONS.get(b));
  return joinedNames(days.map((day) => `le ${day}`));
}

function scheduleSuffix(item) {
  const days = frenchDays(item.facts.days);
  const start = frenchClock(item.facts.startTime);
  const end = frenchClock(item.facts.endTime);
  const parts = [];
  if (days !== null) parts.push(days);
  if (start !== null && end !== null) parts.push(`de ${start} à ${end}`);
  else if (start !== null) parts.push(`à partir de ${start}`);
  return parts.join(" ");
}

function joinedSchedules(values) {
  const clean = values.filter((value) => value.length > 0);
  return joinedNames(clean);
}

function naturalRoutineSentence(requested, routines, subject) {
  const subjectName = subject.facts.displayName;
  const isPrimary = subject.facts.personRole === "primary";
  if (requested.kind === "work") {
    const schedules = joinedSchedules(routines.map(scheduleSuffix));
    if (schedules.length === 0) return null;
    return isPrimary ? `Tu travailles ${schedules}` :
      `${subjectName} travaille ${schedules}`;
  }
  if (requested.kind === "school") {
    if (typeof subjectName !== "string" || subjectName.trim().length === 0) {
      return null;
    }
    const schedules = joinedSchedules(routines.map(scheduleSuffix));
    return schedules.length === 0 ? null :
      `${subjectName.trim()} va à l’école ${schedules}`;
  }

  const descriptions = routines.map((item) => {
    const title = item.facts.title;
    if (typeof title !== "string" || title.trim().length === 0) return "";
    const suffix = scheduleSuffix(item);
    return suffix.length === 0 ? title.trim() : `${title.trim()} ${suffix}`;
  });
  const schedules = joinedSchedules(descriptions);
  if (schedules.length === 0) return null;
  if (requested.kind === "named" && routines.length === 1) {
    return isPrimary ? `Tu as ${schedules}` :
      `${subjectName} a ${schedules}`;
  }
  return isPrimary ? `Tes activités sont : ${schedules}` :
    `Les activités de ${subjectName} sont : ${schedules}`;
}

function routineKindsFor(requested, subject) {
  if (requested.kind === "work") return new Set(["workSchedule"]);
  if (requested.kind === "school") return new Set(["schoolSchedule"]);
  if (requested.kind === "activity") {
    return subject.facts.personRole === "primary" ?
      new Set(["personalActivity"]) : new Set(["childActivity"]);
  }
  return null;
}

function canonicalRoutineProfileAnswer(request) {
  const context = request.conversationContext;
  const routineContext = currentRoutineItems(context);
  const requested = requestedRoutineProfileFact(
      request.message, routineContext.items);
  if (requested === null || routineContext.truncated) return null;
  const {people, relations} = currentPeopleAndRelations(context);
  const subject = routineSubject(requested, people, relations);
  if (subject === null) return null;
  const kinds = routineKindsFor(requested, subject);
  let selected = routineContext.items.filter((item) =>
    item.facts.subjectNodeId === subject.facts.nodeId &&
    (kinds === null || kinds.has(item.facts.routineKind)));
  if (requested.namedTitles.size > 0 &&
      (requested.kind === "named" ||
       requested.kind === "activity" && !requested.broadActivity)) {
    selected = selected.filter((item) =>
      requested.namedTitles.has(item.facts.title));
  }
  if (selected.length === 0) return null;
  const sentence = naturalRoutineSentence(requested, selected, subject);
  if (sentence === null) return null;

  const routineFactKeys = ["title", "days", "startTime", "endTime"]
      .filter((key) => selected.some((item) =>
        typeof item.facts[key] === "string"));
  const groundingReferences = routineFactKeys.map((factKey) => ({
    schemaVersion: 1,
    sourceType: "lifeContextRoutine",
    section: "routine",
    factKey,
    freshness: routineContext.stale ? "stale" : "current",
    confirmation: "confirmed",
    projectionVersion: context.projectionVersion,
  }));
  const usedSourceTypes = ["lifeContextRoutine"];
  if (subject.facts.personRole !== "primary") {
    groundingReferences.push({
      schemaVersion: 1,
      sourceType: "lifeContextHuman",
      section: "human",
      factKey: "displayName",
      freshness: "current",
      confirmation: "confirmed",
      projectionVersion: context.projectionVersion,
    });
    usedSourceTypes.push("lifeContextHuman");
  }
  const routineReferenceIndexes = routineFactKeys
      .map((_, index) => index)
      .slice(0, 3);
  const personalClaims = [{
    claimId: "profile-routine-schedule",
    category: "routineFact",
    sourceReferenceIndexes: routineReferenceIndexes,
    certainty: routineContext.stale ? "stale" : "grounded",
  }];
  if (subject.facts.personRole !== "primary") {
    personalClaims.push({
      claimId: "profile-routine-person",
      category: "humanFact",
      sourceReferenceIndexes: [groundingReferences.length - 1],
      certainty: "grounded",
    });
  }
  const visibleText = routineContext.stale ?
    `D’après les dernières informations de ton profil, ` +
      `${sentence.charAt(0).toLowerCase()}${sentence.slice(1)}.` :
    `${sentence}.`;
  return {
    visibleText,
    actions: [],
    memories: [],
    epistemic: {
      schemaVersion: 1,
      responseKind: routineContext.stale ? "answerWithCaveat" : "answer",
      epistemicState: routineContext.stale ? "stale" : "grounded",
      confidenceLevel: routineContext.stale ? "medium" : "high",
      usedSourceTypes,
      groundingReferences,
      personalClaims,
      missingInformation: [],
      contradictions: [],
      clarification: null,
      uncertaintyCodes: routineContext.stale ? ["staleSource"] : [],
      contextStateObserved: context.state,
      warningCodes: [],
      responseId: `profile-routine-${context.projectionVersion}`,
    },
  };
}

function requestedPersonalProfileFact(message) {
  const text = normalizedText(message);
  if (!asksQuestion(text)) return null;
  if (/\b(situation|statut)\s+familial(?:e)?\b/.test(text)) {
    return {
      factKey: "familyStatus",
      category: "humanFact",
      format: naturalFamilyStatus,
      answer: (value) => value,
    };
  }
  if (/\b(situation|statut)\s+professionnel(?:le)?\b/.test(text) ||
      /\b(quel(?:le)? est )?(?:mon|ma) (?:metier|profession)\b/.test(text)) {
    return {
      factKey: "workStatus",
      category: "humanFact",
      format: naturalWorkStatus,
      answer: (value) => value,
    };
  }
  return null;
}

function joinedNames(names) {
  if (names.length === 0) return "";
  if (names.length === 1) return names[0];
  return `${names.slice(0, -1).join(", ")} et ${names[names.length - 1]}`;
}

function currentFamilyComposition(context, primaryItem) {
  const primaryNodeId = primaryItem && primaryItem.facts &&
    primaryItem.facts.nodeId;
  if (typeof primaryNodeId !== "string") {
    return {partners: [], children: [], usesDetails: false};
  }

  const people = new Map();
  for (const section of context.sections) {
    if (section.type !== "human" || section.availability !== "available" ||
        section.freshness !== "current") {
      continue;
    }
    for (const item of section.items) {
      const {nodeId, displayName} = item.facts;
      if (item.type === "person" && item.confirmation === "confirmed" &&
          item.freshness === "current" && typeof nodeId === "string" &&
          typeof displayName === "string" && displayName.trim().length > 0) {
        people.set(nodeId, displayName.trim());
      }
    }
  }

  const partners = new Set();
  const children = new Set();
  for (const section of context.sections) {
    if (section.type !== "relation" || section.availability !== "available" ||
        section.freshness !== "current") {
      continue;
    }
    for (const item of section.items) {
      if (item.type !== "relation" || item.confirmation !== "confirmed" ||
          item.freshness !== "current") {
        continue;
      }
      const {relationRole, sourceNodeId, targetNodeId} = item.facts;
      if (typeof relationRole !== "string" ||
          typeof sourceNodeId !== "string" ||
          typeof targetNodeId !== "string") {
        continue;
      }
      if (["partner", "spouse"].includes(relationRole)) {
        const otherNodeId = sourceNodeId === primaryNodeId ? targetNodeId :
          targetNodeId === primaryNodeId ? sourceNodeId : null;
        const name = otherNodeId === null ? null : people.get(otherNodeId);
        if (name !== null && name !== undefined) partners.add(name);
      }
      if (relationRole === "child" && sourceNodeId === primaryNodeId) {
        const name = people.get(targetNodeId);
        if (name !== undefined) children.add(name);
      }
    }
  }

  return {
    partners: [...partners],
    children: [...children],
    usesDetails: partners.size > 0 || children.size > 0,
  };
}

function naturalFamilyStatus(value, composition = {}) {
  const text = normalizedText(value);
  if (/\b(seule|seul)\b/.test(text)) return "Tu vis seule";
  const partners = Array.isArray(composition.partners) ?
    composition.partners : [];
  const children = Array.isArray(composition.children) ?
    composition.children : [];
  if (text.includes("monoparent")) {
    return children.length > 0 ? `Tu vis seule avec ${joinedNames(children)}` :
      "Tu vis seule avec tes enfants";
  }
  if (text.includes("enfant")) {
    const familyNames = [...partners, ...children];
    return familyNames.length > 0 ?
      `Tu vis en famille avec ${joinedNames(familyNames)}` :
      "Tu vis en famille avec tes enfants";
  }
  if (text.includes("couple") || text.includes("partenaire")) {
    return partners.length > 0 ?
      `Tu vis en couple avec ${joinedNames(partners)}` : "Tu vis en couple";
  }
  if (text.includes("autre") || text.includes("compli")) {
    return "Tu as indiqué une autre situation familiale";
  }
  return null;
}

function naturalWorkStatus(value) {
  const text = normalizedText(value);
  if (text.includes("ne travaille pas")) {
    return "Tu ne travailles pas actuellement";
  }
  if (text.includes("salarie")) return "Tu es salariée";
  if (text.includes("entrepreneuse") || text.includes("entrepreneur")) {
    return "Tu es entrepreneuse";
  }
  if (text.includes("etudiante") || text.includes("etudiant")) {
    return "Tu es étudiante";
  }
  if (text.includes("maison") || text.includes("foyer")) {
    return "Tu es actuellement au foyer";
  }
  if (text.includes("recherche") || text.includes("autre")) {
    return "Tu es actuellement dans une autre situation professionnelle " +
      "ou en recherche";
  }
  return null;
}

function frenchDate(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (parsed.getUTCFullYear() !== year ||
      parsed.getUTCMonth() !== month - 1 ||
      parsed.getUTCDate() !== day) {
    return null;
  }
  return `${day} ${MONTHS[month - 1]} ${year}`;
}

function canonicalProfileFactAnswer(request) {
  const personFactAnswer = canonicalPersonFactAnswer(request);
  if (personFactAnswer !== null) return personFactAnswer;
  const routineFactAnswer = canonicalRoutineProfileAnswer(request);
  if (routineFactAnswer !== null) return routineFactAnswer;
  const requested = requestedRelationshipDate(request.message) ||
    requestedPersonalProfileFact(request.message);
  if (requested === null) return null;

  const context = request.conversationContext;
  const candidates = [];
  for (const section of context.sections) {
    if (section.type !== "human" ||
        !["available", "availableStale"].includes(section.availability)) {
      continue;
    }
    for (const item of section.items) {
      const value = item.facts[requested.factKey];
      if (typeof value !== "string" || requested.format(value) === null ||
          !["confirmed", "needsConfirmation"].includes(item.confirmation)) {
        continue;
      }
      candidates.push({section, item, value});
    }
  }

  const values = [...new Set(candidates.map((candidate) => candidate.value))];
  if (values.length !== 1) return null;
  const candidate = candidates.find((item) => item.value === values[0]);
  const stale = candidate.section.freshness === "stale" ||
      candidate.item.freshness === "stale";
  const confirmation = candidate.item.confirmation;
  const certain = confirmation === "confirmed";
  const familyComposition = requested.factKey === "familyStatus" ?
    currentFamilyComposition(context, candidate.item) : null;
  const formatted = requested.format(candidate.value, familyComposition);
  const answer = requested.answer(formatted);
  const qualifiedAnswer = answer.charAt(0).toLowerCase() + answer.slice(1);
  const visibleText = stale || !certain ?
    `D’après les dernières informations de ton profil, ${qualifiedAnswer}.` :
    `${answer}.`;

  const sourceType = "lifeContextHuman";
  const groundingReferences = [{
    schemaVersion: 1,
    sourceType,
    section: "human",
    factKey: requested.factKey,
    freshness: stale ? "stale" : "current",
    confirmation,
    projectionVersion: context.projectionVersion,
  }];
  const usedSourceTypes = [sourceType];
  const sourceReferenceIndexes = [0];
  if (familyComposition !== null && familyComposition.usesDetails === true) {
    groundingReferences.push({
      schemaVersion: 1,
      sourceType,
      section: "human",
      factKey: "displayName",
      freshness: "current",
      confirmation: "confirmed",
      projectionVersion: context.projectionVersion,
    });
    groundingReferences.push({
      schemaVersion: 1,
      sourceType: "lifeContextRelation",
      section: "relation",
      factKey: "relationRole",
      freshness: "current",
      confirmation: "confirmed",
      projectionVersion: context.projectionVersion,
    });
    usedSourceTypes.push("lifeContextRelation");
    sourceReferenceIndexes.push(1, 2);
  }
  return {
    visibleText,
    actions: [],
    memories: [],
    epistemic: {
      schemaVersion: 1,
      responseKind: stale || !certain ? "answerWithCaveat" : "answer",
      epistemicState: stale ? "stale" :
        certain ? "grounded" : "groundedPartial",
      confidenceLevel: stale || !certain ? "medium" : "high",
      usedSourceTypes,
      groundingReferences,
      personalClaims: [{
        claimId: `profile-${requested.factKey}`,
        category: requested.category,
        sourceReferenceIndexes,
        certainty: stale || !certain ? "groundedPartial" : "grounded",
      }],
      missingInformation: [],
      contradictions: [],
      clarification: null,
      uncertaintyCodes: stale ? ["staleSource"] :
        !certain ? ["unconfirmedSource"] : [],
      contextStateObserved: context.state,
      warningCodes: [],
      responseId: `profile-${requested.factKey}-${context.projectionVersion}`,
    },
  };
}

module.exports = {
  canonicalProfileFactAnswer,
  requestedRoutineProfileFact,
  requestedPersonFact,
  requestedPersonalProfileFact,
  requestedRelationshipDate,
};
