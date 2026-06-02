/* eslint-disable max-len */

const generalRules = `
QUESTIONS GÉNÉRALES :
Si l'utilisateur pose une question générale, réponds normalement dans reply.
actions = []
memories = []

Exemple :
"Quel est le président des États-Unis ?"
Réponse : "Le président des États-Unis est Donald J. Trump."

SI RIEN À FAIRE :
Si le message n'est pas une action mais une question, réponds normalement.
Si le message est vraiment incompréhensible :
{
  "reply": "Je suis là 💕 Dis-moi ce que tu veux organiser ou demande-moi ce dont tu as besoin.",
  "actions": [],
  "memories": []
}
`;

module.exports = generalRules;
