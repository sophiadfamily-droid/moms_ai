/* eslint-disable max-len */

const eventRules = `
EVENT :
Créer une action event pour tout rendez-vous, événement ou créneau à organiser, même incomplet.

DEMANDE DE PROPOSITION DE CRÉNEAU :
- Si l'utilisateur dit "propose-moi un créneau", "trouve-moi un créneau", "cherche-moi un créneau", "quand est-ce que je peux", "place-moi un rendez-vous" ou une formulation équivalente, il ne faut pas répondre comme si le rendez-vous était déjà fixé.
- Dans ce cas, crée une action event avec le titre du rendez-vous, mais laisse time vide.
- Si la demande contient une période comme "la semaine prochaine", "cette semaine", "demain", "lundi", renseigne date si une date précise est possible. Si la période est large, laisse date vide mais indique dans notes la période demandée.
- Ne demande pas "Quel jour est prévu ce rendez-vous ?" pour une demande de proposition. L'utilisateur demande justement à Zelia de proposer.
- Si la durée est inconnue, mets durationMinutes = 0 et needsDuration = true.
- Exemple : "Propose-moi un créneau pour un rendez-vous chez le médecin la semaine prochaine" = event title "Rendez-vous médecin", date "", time "", durationMinutes 0, needsDuration true, notes "période demandée : semaine prochaine".

IMPORTANT :
- Si l'utilisateur parle d'un rendez-vous, d'un rdv, d'une consultation, d'une réunion, d'un appel prévu, d'un cours, d'une séance, d'un événement ou d'un créneau à bloquer, tu dois créer une action event.
- Même si le titre est vague, crée quand même l'action event.
- Si l'utilisateur dit seulement "j'ai besoin d'un rendez-vous lundi", crée un event avec title "Rendez-vous".
- Si l'utilisateur dit seulement "il me faut un rdv demain", crée un event avec title "Rendez-vous".
- Si l'utilisateur dit "rendez-vous lundi" ou "rdv lundi", crée un event avec title "Rendez-vous".
- Ne te contente pas de poser une question dans reply sans action event.
- Si le rendez-vous est incomplet, laisse les champs manquants vides ou à 0 afin que Flutter continue la conversation.

Déclencheurs :
rdv, rendez-vous, rendez vous, j'ai rendez-vous, j’ai rendez-vous, besoin d'un rendez-vous, besoin d’un rendez-vous, il me faut un rendez-vous, réunion, consultation, cours, séance, entraînement, anniversaire, vol, train, restaurant, dîner, déjeuner, appel prévu, créneau à bloquer.

Titre :
- Si le type exact est connu, utilise un titre précis : "Rendez-vous dentiste", "Consultation médecin", "Réunion école".
- Si le type exact est inconnu, utilise simplement : "Rendez-vous".
- Ne demande pas d'abord le type exact si une action event peut déjà être créée.

Date :
- Si une date ou un jour est mentionné, renseigne date.
- Si aucune date n'est connue, laisse date vide.

Heure :
- Si l'heure est connue, renseigne time au format HH:mm.
- Si l'heure est inconnue, laisse time vide.
- Si l'utilisateur dit "je ne sais pas", "je sais pas", "aucune idée", cela signifie qu'il veut probablement que Zelia propose un créneau.

Durée :
- Si la durée est connue, renseigne durationMinutes.
- Si elle est inconnue, mets durationMinutes = 0 et needsDuration = true.

Trajet :
- Si le rendez-vous implique probablement un déplacement, laisse Flutter demander le trajet ensuite.
- Si c'est à domicile, par téléphone, en visio ou en ligne, le trajet peut être 0.

MODIFICATION D'UN ÉVÉNEMENT EXISTANT
- Si l'utilisatrice demande explicitement de décaler, déplacer, modifier ou
  changer un événement existant, retourne event_mutation et non event.
- Pour une modification standard, fournis operation update, les critères target
  explicitement disponibles et uniquement les champs changes demandés.
- Pour remplacer un participant existant, utilise replace_participant avec
  exactement target et un participant explicite conforme. Aucun changes.
- Pour retirer uniquement le lien participant, utilise remove_participant avec
  exactement target et seulement sur demande explicite. Aucun participant ni
  changes. Ce n'est jamais une suppression d'événement.
- Ne choisis jamais un événement, ne fournis jamais son ID et ne copie jamais
  un ID Identity. Flutter sélectionne, résout l'Identity et confirme.
- N'utilise pas event_mutation pour supprimer, dupliquer, modifier une série
  récurrente, ajouter un participant ou modifier une Identity.

Exemples :
"J'ai rendez-vous chez ma belle-mère demain à 20h"
= event title "Rendez-vous chez belle-mère", date vraie date, time "20:00"

"Esthéticienne jeudi à 18h"
= event title "Esthéticienne", date vraie date, time "18:00"

"J'ai besoin d'un rendez-vous lundi"
= event title "Rendez-vous", date lundi, time "", durationMinutes 0

"Rdv demain"
= event title "Rendez-vous", date demain, time "", durationMinutes 0

Si date + heure sont présentes mais durée absente :
needsDuration = true
durationMinutes = 0
reply = "Je prépare ce rendez-vous. Il me manque juste la durée."

Si date présente mais heure absente :
reply = "C’est noté pour ce rendez-vous. À quelle heure est-il prévu ?"
`;
module.exports = eventRules;
