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
  → séparation bornée des demandes autonomes explicitement reconnaissables
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

Le même arbitre détermine ensuite de quel élément du rendez-vous l'utilisatrice
parle : motif, jour, heure, durée, trajet aller, trajet retour ou marge. Si
Zélia demande le motif et que l'utilisatrice répond `en fait 15 heures`, elle
corrige l'heure et repose uniquement la question du motif. Une date et une
heure données ensemble sont appliquées ensemble. Les réponses courtes qui
dépendent réellement de la question, comme `une heure` pour une durée, restent
interprétées dans ce contexte. Cette règle évite qu'une correction valide soit
enregistrée dans le mauvais champ.

Lorsque le calcul automatique des trajets est autorisé, une création Event à
heure fixe ne suit plus le questionnaire manuel durée, trajet aller, trajet
retour et marge. Zélia demande uniquement le lieu s'il manque. Une durée
absente reçoit l'estimation de travail bornée de 60 minutes, visible dans le
récapitulatif. Les trajets sont ensuite calculés depuis l'Event localisé
précédent, ou le domicile, puis vers l'Event localisé suivant, ou le domicile.
Un lieu déjà présent dans la phrase est conservé sans être ajouté au motif. Un
échec de calcul redemande une adresse précise et ne revient pas aux questions
manuelles de trajet. Sans autorisation de calcul, le parcours historique reste
inchangé.

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

## Plusieurs demandes dans un message

La session peut séparer au maximum trois demandes autonomes reliées par une
ponctuation ou un connecteur explicite (`puis`, `ensuite`, `et aussi`, ou `et`
devant une nouvelle commande). Les commandes conservent leurs variantes
accentuées et naturelles, y compris `mémorise`, `n’oublie pas`, `garde en
mémoire` et `à partir de maintenant`. Chaque fragment suivant doit porter sa
propre commande et être reconnu de manière déterministe comme Event, Task,
Shopping ou Memory. Une liste d'articles ou plusieurs éléments d'un même
domaine restent intacts pour leur parseur spécialisé. Une négation, un fragment
incertain ou un message trop long n'est jamais découpé arbitrairement.

Le message original est affiché une seule fois. Les demandes reconnues sont
traitées dans leur ordre, avec une identité logique distincte. Si la première
demande nécessite une précision ou un accord, les suivantes attendent. Une
réponse contextuelle peut terminer la question en cours avant qu'une nouvelle
commande explicite du même message soit exécutée. Cette file ne confirme, ne
persiste et n'exécute rien elle-même : chaque domaine conserve ses validations,
son écriture idempotente et ses règles d'autorisation. Une consigne de mémoire
explicite et immédiatement enregistrée libère la file sans demander un second
accord. Une commande Shopping directe, complète et non ambiguë (`ajoute … aux
courses`) vaut également autorisation fraîche pour cet ajout réversible et
s'exécute sans un second `oui`. Un constat de rupture de stock, une ambiguïté,
une négation, une contradiction ou une action plus risquée conserve sa
clarification ou sa confirmation propre.

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
correction phonétique ouverte, de segmentation libre ou probabiliste de
plusieurs actions, de résolution arbitraire de pronom, de rapprochement flou de
nom propre ni d’inférence de lieu/personne. La séparation multi-demande reste
bornée aux commandes explicites et aux domaines déterministes. Routine conserve une normalisation
horaire spécialisée parce que sa ponctuation et ses plages font partie de son
contrat. Les expressions contextuelles telles qu’`après l’école` ne doivent
pas inventer une disponibilité universelle ; le moteur métier doit demander
ou utiliser une valeur explicitement confirmée.
