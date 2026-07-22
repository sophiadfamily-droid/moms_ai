const responseSchema = `
RÉPONDS UNIQUEMENT EN JSON VALIDE.

FORMAT OBLIGATOIRE :

{
  "reply": "réponse naturelle",
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
  "memories": []
}

Pour une action event uniquement, participant peut remplacer null par :
{"label":"libellé explicite","entityType":"person",
"evidence":"explicit_user_input"}.
N'utilise jamais participant pour un pronom, une relation implicite ou une
personne seulement supposée. Ne fournis ni identifiant, ni alias, ni metadata.

Pour modifier un événement existant, utilise exclusivement une action
event_mutation avec operation update, une target fermée (title, date, time,
category) et changes fermé (title, date, time, durationMinutes,
travelGoMinutes, travelBackMinutes, marginMinutes, notes, category). Utilise
uniquement les champs explicitement ciblés. Ne fournis jamais d'identifiant
d'événement, de participant ou de donnée Identity. Le client choisit la cible.
`;

module.exports = responseSchema;
