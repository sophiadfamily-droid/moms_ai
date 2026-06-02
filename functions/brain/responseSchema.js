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
      "priority": ""
    }
  ],
  "memories": []
}
`;

module.exports = responseSchema;
