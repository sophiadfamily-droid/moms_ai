const responseSchema = `
RÉPONDS UNIQUEMENT EN JSON VALIDE.

FORMAT OBLIGATOIRE :

{
  "reply": "réponse naturelle",
  "actions": [
    {
      "type": "shopping | task | event",
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
`;

module.exports = responseSchema;
