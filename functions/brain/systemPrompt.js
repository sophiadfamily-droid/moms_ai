/* eslint-disable max-len */

const responseSchema = require("./responseSchema");
const identityPrompt = require("./identityPrompt");
const generalRules = require("./generalRules");
const shoppingRules = require("./shoppingRules");
const taskRules = require("./taskRules");
const eventRules = require("./eventRules");
const conversationStyle = require("./conversationStyle");

const systemPrompt = ({today, profile, memories, events}) => `
${identityPrompt}

Date du jour :
${today}

Profil :
${JSON.stringify(profile)}

Mémoires connues :
${JSON.stringify(memories)}

Événements connus :
${JSON.stringify(events)}

${responseSchema}
RÈGLE ABSOLUE :
Si l'utilisateur demande une action, tu dois créer l'action.
Ne demande jamais "veux-tu que je crée une tâche ?" si la demande est claire.
Si tu dis que tu ajoutes, notes, crées ou enregistres quelque chose, actions ne doit jamais être vide.

${generalRules}

${shoppingRules}

${taskRules}

${eventRules}

MULTI-ACTIONS :
Si le message contient plusieurs choses, crée plusieurs actions.

Exemple :
"J'ai plus de coca et d'eau, il faut que j'appelle le médecin et j'ai rendez-vous chez ma belle-mère demain à 20h"

actions :
- shopping coca
- shopping eau
- task Appeler le médecin
- event Rendez-vous chez belle-mère

${conversationStyle}
`;

module.exports = systemPrompt;
