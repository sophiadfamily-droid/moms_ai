const responseSchema = `
RÉPONDS UNIQUEMENT EN JSON VALIDE.

FORMAT OBLIGATOIRE :

{
  "visibleText": "réponse naturelle",
  "actions": [
    {
      "type": "shopping | task | event | event_mutation",
      "title": "titre court",
      "date": "",
      "time": "",
      "durationMinutes": 0,
      "needsDuration": false,
      "isRecurring": false,
      "recurringType": "",
      "recurringWeekday": 0,
      "category": "",
      "notes": "",
      "isImportant": false,
      "dueDate": "",
      "planning": "",
      "priority": "",
      "participant": null
    }
  ],
  "memories": [],
  "epistemic": {
    "schemaVersion": 1,
    "responseKind": "answer",
    "epistemicState": "grounded",
    "confidenceLevel": "high",
    "usedSourceTypes": ["currentUserMessage"],
    "groundingReferences": [{
      "schemaVersion": 1,
      "sourceType": "currentUserMessage",
      "section": null,
      "factKey": null,
      "freshness": "current",
      "confirmation": "confirmed",
      "projectionVersion": 0
    }],
    "personalClaims": [],
    "missingInformation": [],
    "contradictions": [],
    "clarification": null,
    "uncertaintyCodes": [],
    "contextStateObserved": "complete",
    "warningCodes": [],
    "responseId": "identifiant-technique-aléatoire"
  }
}

Adapte contextStateObserved exactement à l'enveloppe reçue. Les références
Life Context utilisent le nom de section, la clé de fait et projectionVersion
réellement présents. N'invente aucune référence.

Pour une action event uniquement, participant peut remplacer null par :
{"label":"libellé explicite","entityType":"person",
"evidence":"explicit_user_input"}.
N'utilise jamais participant pour un pronom, une relation implicite ou une
personne seulement supposée. Ne fournis ni identifiant, ni alias, ni metadata.

Pour modifier un événement existant, utilise exclusivement event_mutation.
update porte target + changes fermés. replace_participant porte target et un
participant explicite conforme, sans changes. remove_participant porte seulement
target et retire le lien participant, jamais l'événement. Ne fournis jamais
d'identifiant Event ou Identity. Le client choisit la cible et l'Identity.
`;

module.exports = responseSchema;
