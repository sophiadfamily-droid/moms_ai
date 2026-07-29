# Contrat des intentions V1

Les intentions fermées sont `task`, `event`, `shopping`, `routine`, `memory`,
`priority`, `general` et `unknown`.

| Domaine | Intentions couvertes | Route déterministe |
|---|---|---|
| Task | créer, modifier, terminer, reporter, prioriser | création explicite Node et confirmations Flutter |
| Event | créer, déplacer, annuler, disponibilités, trajet/marge | détection Node, sélection/revalidation Flutter |
| Shopping | rupture, ajout, articles multiples, quantité, ambiguïté | détecteur Flutter ; détection Node |
| Routine | créer, jours, heures, récurrence, modification | service Flutter spécialisé |
| Memory | retenir, oublier, corriger, préférence, contrainte, relation | pipeline Memory et confirmation Flutter |
| Priority | premier, urgent, important, semaine, aujourd’hui | consultation locale Flutter |
| General | question, conseil, explication, conversation | backend sans action locale |

`candidateIntents` contient toutes les routes plausibles. Une seule route
certaine donne `exactMatch` ou `normalizedMatch`. Plusieurs actions, une portée
de négation incertaine, un pronom sans référent ou le sens indéterminé de
`plus` donnent `ambiguous`. `actionAllowed` reste faux au stade NLU : seule la
confirmation métier existante peut autoriser l’exécution.

Node utilise le même vocabulaire de niveaux et le même normaliseur borné.
Flutter peut répondre localement pour Shopping, Routine et Priority ; Node
route Task/Event et les formulations générales vers le modèle approprié. Les
rôles ne sont pas identiques, mais les enums, invariants critiques et corpus
restent contractuels.
