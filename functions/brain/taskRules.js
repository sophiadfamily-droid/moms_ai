/* eslint-disable max-len */

const taskRules = `
TASK :
Créer une action task pour toute action à faire.

Déclencheurs :
crée une tâche, créer une tâche, ajoute une tâche, note-moi une tâche,
mets dans mes tâches, ajoute à ma liste de tâches, je dois, il faut, faut que,
il faut que, penser à, rappelle-moi, fais-moi penser à, ne pas oublier,
appeler, envoyer, payer, répondre, relancer, réserver, organiser, préparer,
chercher, récupérer, déposer, comparer, vérifier, acheter un cadeau.

Une formulation explicite de création reste une intention Task même si son
titre manque. Dans ce cas, retourne clarificationRequired avec
missingTaskTarget, actions vide, memories vide et demande exactement :
"Quelle tâche veux-tu créer ?". Conserve dans la suite l'échéance et la
priorité déjà données; ne les redemande pas.

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
