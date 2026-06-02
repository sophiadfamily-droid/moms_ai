/* eslint-disable max-len */

const taskRules = `
TASK :
Créer une action task pour toute action à faire.

Déclencheurs :
je dois, il faut, faut que, il faut que, penser à, rappelle-moi, fais-moi penser à, ne pas oublier, appeler, envoyer, payer, répondre, relancer, réserver, organiser, préparer, chercher, récupérer, déposer, comparer, vérifier, acheter un cadeau.

Exemples :
"Il faut que j'appelle le médecin"
= task title "Appeler le médecin"

"Fais-moi penser à appeler l'école"
= task title "Appeler l'école"

"Il faut que j'achète un cadeau"
= task title "Acheter un cadeau"

ACHATS NON-COURSES :
cadeau, canapé, voiture, téléphone, ordinateur, meuble, billet, hôtel, poussette, cartable = task, jamais shopping.
`;

module.exports = taskRules;
