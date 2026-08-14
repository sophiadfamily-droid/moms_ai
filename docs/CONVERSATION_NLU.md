# Conversation et compréhension naturelle V1

## Contrat

Le texte utilisateur reste l’autorité. `NaturalLanguageNormalizer` conserve
toujours `originalText` et produit une projection bornée : `normalizedText`,
`tokens`, `detectedLanguage`, `normalizationCodes` et
`preservedAmbiguities`. La projection sert au routage déterministe ; le texte
original reste utilisé pour le contexte, l’affichage et la provenance.

Les niveaux sont fermés :

- `exactMatch` : formulation canonique reconnue sans transformation ;
- `normalizedMatch` : même sens après une transformation sûre ;
- `probableMatch` : sens très probable, jamais directement exécutable ;
- `ambiguous` : plusieurs sens ou une portée de négation incertaine ;
- `noMatch` : aucune route locale certaine, donc route générale/backend.

Un score numérique peut aider à classer une proposition historique, mais ne
peut jamais autoriser une action. Toute création, modification ou suppression
continue de passer par le récapitulatif, la confirmation explicite, la
revalidation, l’idempotence et la portée de compte existants.

## Pipeline

```text
message brut / transcription éditable
  → normalisation sûre (original conservé)
  → arbitrage du rôle du tour (répondre, corriger, refuser, abandonner, changer de demande)
  → détection locale déterministe
  → clarification bornée si ambiguïté critique
  → backend si aucune route locale certaine
  → validation du contrat d’intention et des entités
  → proposition métier structurée
  → confirmation explicite
  → revalidation du contexte
  → écriture idempotente
```

## Audit du pipeline avant V1-NLU.1

| ÉTAPE | COMPOSANT | ENTRÉE | NORMALISATION | INTENTION | CONFIANCE | FALLBACK | RISQUE |
|---|---|---|---|---|---|---|---|
| saisie/voix | `ChatScreen`, `VoiceRecognitionCoordinator` | texte éditable | aucune décision métier | aucune | n/a | envoi Conversation | transcription bruitée |
| orchestration | `ConversationCoordinator` | message + continuation | détecteurs privés | Shopping, Routine, Priority, confirmations | enums locales | backend | divergence des règles |
| entités planning | `NaturalLanguageUnderstandingService` | texte original | accents/casse privée | aucune | score numérique | champs backend | score opaque, expressions dictées manquantes |
| shopping local | `ShoppingConversationIntentDetector` | message | table locale étendue | rupture/ajout/`plus` | enum fermée | backend | divergence Node |
| routine locale | `RoutineConversationService` | message + pending | grammaire horaire spécialisée | routine/continuation | état typé | backend | ponctuation nécessaire |
| priorité locale | `PriorityConsultationIntentDetector` | message | table locale | consultation | booléen | backend | vocabulaire borné |
| backend | `intentDetector` | message | normalisation JS privée | Task/Event/Shopping/General | score numérique | modèle | négation et `plus` insuffisamment fermés |
| validation | contrats Response + gardes Flutter | actions générées | champs structurés | action métier | contrats fermés | rejet/clarification | aucune exécution avant confirmation |

Après V1-NLU.1, Shopping, Priority, réponses oui/non, NLU Planning et Node
partagent le contrat de normalisation. Routine conserve seulement sa grammaire
spécialisée. Node bloque déterministement les ambiguïtés critiques avant le
modèle. Flutter refuse d’appliquer les entités Planning marquées ambiguës.

Une continuation active n’a priorité que si sa forme est compatible avec le
champ attendu. Une réponse simple (`oui`, `ouais`, `yep`, `d’accord`, `vas-y`,
`non`, `nan`, `laisse tomber`) peut résoudre un oui/non. Une réponse composée
(`oui mais demain`, `non plutôt mardi`, `peut-être`) reste ambiguë et doit être
interprétée selon son contenu. Une question indépendante, par exemple
`quelles sont mes priorités ?`, n’est pas capturée comme réponse de champ.

Avant toute consommation d'un champ Event, `ConversationTurnIntentService`
interprète le rôle de la phrase entière. Une formule autonome d'abandon
(`annul`, `arrête`, `j'ai changé d'avis`) ferme le brouillon sans devenir un
titre. Une action portant une cible (`annule mon rendez-vous de lundi`) change
de demande et retourne au routage général. Une reprise (`en fait dentiste`,
`je voulais dire 15 h`, `change pour vendredi`) fournit seulement son contenu
utile au champ courant. Une commande de contrôle niée (`n'annule pas`) reste
non exécutable et ne supprime rien. Cette couche est prioritaire sur le type de
champ attendu : Zélia comprend d'abord ce que fait l'utilisatrice dans la
conversation, puis seulement la valeur qu'elle donne.

## Normalisations autorisées

Sont autorisés : casse, accents, variantes d’apostrophes, tirets, espaces,
ponctuation légère, emoji léger, contractions françaises bornées, formes SMS
listées (`rdv`, `mtn`, `stp`, `svp`, `ajd`), fautes sûres portant sur la
grammaire de commande ou de temps (`dem1`, `dmain`, `rendezvous`, `crenau`,
`14 hure`, `sem proch`) et heures dictées déterministes. Les parseurs locaux de
date, d’heure, de durée et de recherche de créneau consomment cette même
projection ; la règle est donc générale pour toutes les valeurs reconnues, et
non liée à une heure ou à un rendez-vous précis. Flutter et Node partagent les
mêmes cas de contrat.

Ne sont jamais corrigés arbitrairement : noms propres, personnes, lieux,
titres libres ou mots proches d’une action sensible. La négation n’est jamais
supprimée. Les sens de `plus` sont conservés comme ambiguïté lorsque le
contexte ne suffit pas. Une phrase multi-action est clarifiée si elle ne peut
pas être séparée sans risque.

## Entités

Une entité structurée contient son type, son extrait original, sa valeur
normalisée, un niveau fermé (`exactMatch`, `normalizedMatch`,
`probableMatch`, `ambiguous`), une provenance et une ambiguïté éventuelle.
Les parseurs déterministes actuels exposent date, heure et durée. Les actions
backend conservent leurs champs structurés pour articles, quantités,
personnes, lieux, titres, priorités, récurrences, trajets et marges ; ces
valeurs ne doivent pas être reconstruites depuis le seul texte du
récapitulatif.

## Clarification

Le contrat Flutter `NaturalLanguageClarification` lie `ambiguityType`,
`candidateIntents`, entités connues, champs manquants, question,
`logicalRequestId`, tentative, expiration et `accountScopeId`. La limite est
de trois tentatives. Le backend lie aussi toute clarification à la génération
de session, fixe une expiration pour les ambiguïtés NLU et retourne zéro
action/mémoire avant résolution.

Une clarification de création Event peut aussi porter
`clarification.draft`, un `ConversationClarificationDraft` fermé et
non exécutable. Le draft `eventCreation` contient uniquement ses identifiants
conversationnels bornés, le titre, les date/heure et durées déjà certaines,
le champ attendu, la génération et une expiration maximale de quinze
minutes. Il ne contient aucun UID, scope de compte, mutationId, actionId ou
état Firestore. `actions` reste vide. Flutter le valide puis l’enregistre dans
la continuation de la session courante ; changement de compte, génération
différente, refus, expiration ou succès le suppriment. L’Event exécutable
n’est construit qu’après complétion, récapitulatif et confirmation.

Une référence (`mets-le demain`), une identité compatible multiple ou une
cible Event multiple exige une clarification. Les résolveurs Identity et
Event existants restent propriétaires de leurs recherches et sélections.

## Diagnostic sans contenu

`component` vaut `natural_language`. Les étapes fermées sont `normalize`,
`detect_intent`, `extract_entities`, `resolve_ambiguity`, `route` et `reject`.
Seuls `normalizationCodes`, `intentCode`, `understandingLevel`,
`entityTypes`, `ambiguityType` et `durationMs` sont admissibles. Texte brut,
transcription, nom, titre, lieu, mémoire et payload sont interdits.

## Corpus et méthode

`functions/test/fixtures/frenchNluCorpus.js` construit 200 exemples
synthétiques versionnés et non personnels : 40 Task, 40 Event/Planning,
35 Shopping, 25 Routine, 25 Memory, 20 Priority et 15 ambiguïtés/négatifs.
Chaque entrée contient texte brut, texte normalisé, intention, entités
attendues, niveau et disposition (`confirmation` ou `clarification`).

La cible de normalisation est 100 %. Les invariants absolus sont zéro action
autorisée sur une ambiguïté et zéro faux positif sur une négation critique.
Le routage métier complet n’est pas mesuré comme une précision statistique
unique : Flutter et Node n’ont pas le même rôle, et les domaines généraux
restent traités par le backend derrière son schéma fermé.

## Limites V1

V1 n’est pas un correcteur orthographique général : l'intention portée par la
phrase et le contexte conversationnel restent prioritaires sur la correction
de surface. Elle ne fait pas de
correction phonétique ouverte, de segmentation automatique de plusieurs
actions, de résolution arbitraire de pronom, de rapprochement flou de nom
propre ni d’inférence de lieu/personne. Routine conserve une normalisation
horaire spécialisée parce que sa ponctuation et ses plages font partie de son
contrat. Les expressions contextuelles telles qu’`après l’école` ne doivent
pas inventer une disponibilité universelle ; le moteur métier doit demander
ou utiliser une valeur explicitement confirmée.
