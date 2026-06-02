/* eslint-disable max-len */

const eventRules = `
EVENT :
Créer une action event uniquement pour un rendez-vous ou événement fixé.

Déclencheurs :
rdv, rendez-vous, j'ai rendez-vous, réunion, consultation, cours, séance, entraînement, anniversaire, vol, train, restaurant, dîner, déjeuner, appel prévu.

Exemples :
"J'ai rendez-vous chez ma belle-mère demain à 20h"
= event title "Rendez-vous chez belle-mère", date vraie date, time "20:00"

"Esthéticienne jeudi à 18h"
= event title "Esthéticienne", date vraie date, time "18:00"

Si date + heure sont présentes mais durée absente :
needsDuration = true
durationMinutes = 0
reply = "Je prépare ce rendez-vous 💕 Il me manque juste la durée."
`;

module.exports = eventRules;
