# Audit de propriété des données de Zélia

Statut : contrat d'architecture et suivi de migration
Version : 2.0
Date : 21 août 2026

Ce document complète `ZELIA_BRAIN_CONTRACT.md` et
`MASTER_ARCHITECTURE.md`. Il décrit l'état physique actuel des données, fixe
leur propriétaire cible et donne l'ordre sûr de migration.

Cette étape ne change aucun écran ni comportement de l'application.

## 1. Conclusion

Zélia possède déjà une fondation solide : les personnes, les événements, les
tâches, les routines et la mémoire peuvent être réunis dans un contexte de vie
central. Ce contexte alimente déjà la conversation et plusieurs moteurs de
raisonnement.

La fondation n'est toutefois pas encore un cerveau entièrement unifié. Les
domaines Courses et Réglages ont maintenant rejoint le contexte de vie, mais
les propriétaires historiques ne sont pas encore tous réduits :

- le profil historique `UserProfile` et le modèle humain `HumanModel`
  représentent encore certaines mêmes informations ;
- les réglages généraux utiles au raisonnement disposent désormais du registre
  canonique `AppSettings`, tandis que les politiques spécialisées conservent
  leur propriétaire dédié ;
- les plannings manuels et importés sont désormais rattachés à leur personne
  dans `HumanModel`, mais certains écrans lisent encore une projection de
  compatibilité `UserProfile` ;
- l'ancienne classe non utilisée `AppDataService` a été retirée ; les tâches,
  les courses et l'agenda ne peuvent plus revenir vers ce stockage local sans
  compte.

La priorité n'est donc pas de réécrire les fonctionnalités. Elle est de donner
à chaque information un seul propriétaire, puis de faire lire tous les moteurs
depuis une projection cohérente.

## 2. Règle d'or

Une information métier possède un seul propriétaire canonique.

- Le propriétaire enregistre, modifie, synchronise et supprime l'information.
- Une projection peut la reformater pour un écran ou un moteur, mais ne devient
  jamais une seconde vérité.
- Le contexte de vie est une vue de lecture : il ne possède aucune donnée.
- Un écran affiche et modifie un domaine par son service ; il ne possède pas la
  donnée.
- Une copie de compatibilité est temporaire, identifiable et dérivable depuis
  la source canonique.
- Une suppression doit atteindre le propriétaire canonique puis disparaître de
  toutes les projections.

## 3. Propriétaires cibles

| Information | État actuel principal | Propriétaire cible | Projections et usages autorisés |
| --- | --- | --- | --- |
| Personnes, liens, foyer, domiciles, responsabilités | `HumanModel`, avec une partie encore reflétée dans `UserProfile` | `HumanModel` | Profil, conversation, disponibilité, suggestions |
| Informations personnelles durables structurées | Réparties entre `HumanModel` et `UserProfile.legacyProfile` | `HumanModel`, dans des champs typés ou des extensions versionnées | Profil et contexte de vie |
| Planning récurrent d'une personne | `HumanPerson.customFields.structuredSchedulesV1` et miroir `UserProfile` | `HumanModel`, rattaché à la personne | Profil, routines, disponibilité ; affichage agenda selon réglage |
| Rendez-vous ou engagement daté de l'utilisatrice | `EventModel` | Domaine Événement | Agenda, conversation, conflits, trajets, suggestions |
| Enveloppe de déplacement d'un événement | `EventModel` | Domaine Événement | Calcul interne et résumé discret ; aller et retour restent distincts |
| Tâches | `TaskModel` | Domaine Tâche | Écran Tâches, dashboard, suggestions, conversation |
| Produits à acheter | `ShoppingItemModel` | Domaine Courses | Écran Courses, dashboard, suggestions, conversation |
| Historique d'achat | Éléments marqués achetés dans le domaine Courses | Domaine Courses, historique masqué par défaut | Analyse d'habitudes avec règles de rétention ; jamais mémoire personnelle |
| Quantité d'un produit | `ShoppingItemModel.quantity` | Domaine Courses | Écran Courses et conversation |
| Routines et exceptions d'occurrence | `RoutineModel` et dépôts de routines | Domaine Routine | Agenda si autorisé, disponibilité, conversation |
| Souvenirs personnels durables | Domaine Mémoire | Domaine Mémoire | Centre mémoire, conversation et personnalisation |
| Langue, notifications, trajets automatiques, marge, choix d'affichage | Profil et plusieurs dépôts `SharedPreferences` | Domaine Réglages explicite | Écrans de réglages et contexte de vie limité aux décisions concernées |
| Identité technique d'une personne | Domaine Identité et identifiants du modèle humain | Domaine Identité, relié à `HumanModel` | Résolution des références et attribution sûre |
| Contexte de vie unifié | Huit adaptateurs actuels | Aucun : projection de lecture | Conversation, propositions, priorités, notifications, anticipation |

## 4. Carte physique actuelle

### 4.1 Modèle humain et profil

`HumanModel` est la structure humaine canonique la plus avancée. Il contient
les personnes, relations, foyers, résidences, appartenances et responsabilités,
avec provenance, confirmation et périodes de validité.

`UserProfile` reste un grand agrégat de compatibilité. Il contient encore :

- des informations qui appartiennent déjà au modèle humain ;
- des préférences et réglages ;
- des horaires de travail et activités ;
- des notes de vie et informations de profil ;
- des représentations historiques du partenaire et des enfants.

L'adaptateur historique migre une partie de `UserProfile` vers `HumanModel`,
mais conserve aussi l'ancien profil complet dans `HumanModel.legacyProfile`.
La projection inverse reconstruit ensuite un `UserProfile` et remplace quelques
champs par les valeurs canoniques. Ce pont protège les écrans existants, mais il
constitue une dette de migration et non l'architecture finale.

Stockage actuel :

- `HumanModel` : dépôt local dédié et document Firestore
  `users/<uid>/private/humanModel` ;
- profil de compatibilité : stockage local anonyme ou lié au compte et profil
  privé révisionné pour les champs dont le profil est encore propriétaire.

### 4.2 Domaines révisionnés

Les événements, tâches et courses disposent de services dédiés avec stockage
local, synchronisation liée au compte, révisions et protections contre les
conflits. Les collections principales sont :

- `users/<uid>/events` ;
- `users/<uid>/tasks` ;
- `users/<uid>/shopping_items`.

Les routines utilisent leurs propres dépôts et la mémoire utilise
`users/<uid>/memories`, avec politique et état de synchronisation locaux.

### 4.3 Import de planning

Après validation, un import structuré peut produire trois représentations :

1. une entrée canonique rattachée à la bonne personne dans `HumanModel` ;
2. un miroir dans `UserProfile` pour les écrans historiques ;
3. un `EventModel` pour une occurrence datée qui est réellement un événement.

La cible est la suivante :

- un planning récurrent ou le planning daté d'une autre personne reste dans le
  contexte de cette personne ;
- un engagement daté appartenant réellement à l'utilisatrice devient un
  événement ;
- un miroir `UserProfile` doit être dérivé et supprimable à terme ;
- le marqueur local d'import sert uniquement à éviter un double traitement ;
- le document ou l'image source n'est pas conservé après extraction validée.

Les entrées datées expirées de planning humain peuvent déjà être nettoyées. Ce
nettoyage doit rester distinct de la mémoire personnelle permanente.

Les horaires manuels historiques — travail de l'utilisatrice, activités,
école et activités des enfants — suivent maintenant le même propriétaire que
les imports. Une migration idempotente les transforme en entrées structurées
rattachées à la bonne personne. Les clés dérivées du contenu évitent les
doublons et une suppression depuis un ancien écran retire seulement le miroir
correspondant, jamais un import indépendant.

Pour préserver les écrans actuels, `UserProfile` est reconstruit depuis ces
horaires canoniques. Le contexte de vie privilégie la source humaine et retire
la copie historique équivalente avant tout raisonnement. Zélia ne peut donc
plus compter deux fois la même école, le même travail ou la même activité.

### 4.4 Ancien stockage sans consommateur

`AppDataService` définissait trois anciennes clés locales, `tasks`, `shopping`
et `agenda`, sous forme de listes simplifiées. Aucun appel actif n'a été trouvé
dans `lib` ou `test`. La classe a donc été retirée et un test d'architecture
interdit son retour.

## 5. Contexte de vie actuel

Le contexte de vie de production réunit actuellement huit domaines :

1. humain ;
2. identité ;
3. événements ;
4. tâches ;
5. routines ;
6. mémoire ;
7. réglages ;
8. courses actives.

Les modifications de ces domaines invalident leurs sections respectives. La
conversation, les priorités et plusieurs mécanismes proactifs peuvent ainsi
raisonner sur une photographie cohérente.

### Manques confirmés

- **Écrans de planning** : plusieurs formulaires historiques modifient encore
  la projection `UserProfile`. Leur lecture et leur mutation devront appeler
  directement le propriétaire humain avant de supprimer ce pont.
- **Courses** : seuls les produits encore actifs sont projetés. L'historique
  acheté reste volontairement dans le domaine Courses et ne rejoint ni le
  contexte de décision courant ni la mémoire personnelle.
- **Profil complet** : plusieurs faits utiles demeurent uniquement dans
  `legacyProfile` ou dans les champs historiques de `UserProfile`.
- **Horizon** : la projection Événement est volontairement bornée à sept jours
  passés et soixante jours futurs. Les besoins de long terme devront utiliser
  une projection dédiée plutôt que rendre toutes les requêtes illimitées.

### Lectures directes acceptables

Un écran peut charger directement son domaine pour afficher et modifier les
données : Agenda avec Événement, Tâches avec Tâche, Courses avec Courses et
Profil avec la projection de profil.

En revanche, une décision qui combine plusieurs domaines — meilleur créneau,
suggestion globale, conflit de vie, anticipation ou réponse personnalisée —
doit partir d'un contexte de vie cohérent. Elle ne doit pas recomposer une
vérité partielle avec plusieurs lectures effectuées à des instants différents.

## 6. Dettes et risques classés

### Priorité 1 — empêche le cerveau unifié

1. Des faits personnels utiles restent enfermés dans le profil historique.
2. Certains moteurs combinent encore directement événements et tâches au lieu
   d'utiliser une projection cohérente pour leur phase de décision.

### Priorité 2 — risque de divergence

1. `HumanModel` et `UserProfile` contiennent encore deux représentations
   transitoires d'une même personne ou d'un même planning, même si la seconde
   est désormais dérivée et dédupliquée avant raisonnement.
2. Les imports et éditions historiques écrivent encore un miroir de
   compatibilité en plus de la source canonique.

### Priorité 3 — nettoyage contrôlé

1. Les libellés et adaptateurs de compatibilité mentionnent encore
   `legacyProfile`.
2. Certaines structures historiques conservent des champs de trajet et de
   notes qui ne correspondent plus aux formulaires simplifiés.

## 7. Architecture cible

```text
Sources canoniques
  HumanModel   Events   Tasks   Shopping   Routines   Memory   Settings
       \          |       |        |          |          |        /
                    Life Context (lecture cohérente)
                               |
          Conversation · Suggestions · Disponibilité · Dashboard
                               |
                    Propositions et explications
                               |
                 Mutation du seul domaine propriétaire
```

Le contexte de vie porte pour chaque fait utile :

- sa source ;
- la personne concernée ;
- sa date de mise à jour et sa période de validité ;
- son niveau de certitude ;
- sa conséquence éventuelle pour l'utilisatrice ;
- son droit d'usage selon le but demandé.

Il ne copie pas les photos, documents sources ou détails sensibles inutiles à
la décision.

## 8. Ordre sûr de migration

### Étape A — figer les contrats

- Ajouter des tests de propriété et de projection autour des comportements
  actuels validés.
- Interdire le retour d'un stockage métier local non lié au compte.
- Inventorier les clés locales et collections avant toute suppression.

### Étape B — créer le domaine Réglages

- Définir un modèle versionné lié au compte.
- Y déplacer progressivement les choix de trajet automatique, marge de
  sécurité, affichage des horaires de travail, école, routines et activités,
  langue et préférences de notification.
- Maintenir temporairement une lecture de compatibilité depuis `UserProfile`.

Progression : étape réalisée pour les réglages généraux dans `AppSettings`,
avec migration idempotente, isolation par compte et projection de
compatibilité. Les réglages spécialisés de notifications, d'autonomie et de
mémoire restent volontairement dans leurs domaines dédiés.

### Étape C — intégrer Courses au contexte de vie

- Ajouter un domaine Courses et son invalidation.
- Projeter seulement les produits actifs et les données nécessaires au but.
- Ajouter la quantité au modèle canonique.
- Garder l'historique acheté masqué, borné et distinct de la mémoire.

Progression : étape réalisée dans la fondation locale. La projection est
bornée aux produits actifs, la quantité est canonique et l'historique acheté
reste exclu du contexte de vie.

### Étape D — achever le modèle humain

- Classer chaque champ utile de `UserProfile` : fait humain, réglage, mémoire ou
  donnée obsolète.
- Migrer les faits humains vers des champs structurés ou des extensions
  versionnées de `HumanModel`.
- Ajouter provenance, validité et certitude quand elles manquent.

Progression : les champs V1 du profil sont maintenant classés par
destination. Les faits personnels durables de l'utilisatrice, du partenaire et
des enfants sont copiés dans une extension humaine versionnée, rattachée à la
bonne personne, avec une provenance par champ. Une information confirmée
directement par l'utilisatrice ne peut plus être remplacée ni effacée par une
ancienne copie du profil. La projection inverse maintient les écrans de profil
actuels sans créer une nouvelle source de vérité.

La situation familiale et la situation professionnelle du profil principal
ont achevé cette transition : le contexte de vie les lit exclusivement sur la
personne canonique. Leur ancienne copie reste temporairement conservée pour la
migration et la reconstruction des écrans, mais ne peut plus modifier une
réponse ou une suggestion lorsque le fait humain canonique est absent.

Restent volontairement hors de cette copie :

- les réglages, qui rejoindront le domaine Réglages ;
- les souvenirs libres, qui appartiennent au domaine Mémoire ;
- les horaires structurés, qui restent dans l'extension de planning humain ;
- les informations de couple, qui restent rattachées à la relation.

La suppression des écritures parallèles dans `UserProfile` appartient à
l'étape E et ne doit intervenir qu'après migration des consommateurs.

Les faits humains utiles rejoignent maintenant le contexte de vie sous forme
de faits séparés et bornés. Une information volumineuse ne peut donc pas faire
disparaître l'identité minimale de la personne. Leur usage est limité par le
but demandé : les adresses peuvent servir à la planification, tandis que les
faits ordinaires peuvent personnaliser une conversation. Les photos, données
médicales, allergies, groupe sanguin, médecin et contacts d'urgence restent
fermés au contexte général. Un futur besoin de santé devra utiliser un contrat
dédié, explicite et plus restrictif.

### Étape E — rendre le profil dérivé

- Faire de `UserProfile` une projection de compatibilité générée depuis
  `HumanModel` et Réglages.
- Supprimer les écritures parallèles une fois tous les écrans migrés.
- Conserver des migrations idempotentes pour les anciennes installations.

Progression : le parcours principal d'édition du profil écrit désormais
`HumanModel` avant de sauvegarder sa vue de compatibilité. La vue historique
n'est mise à jour qu'à partir du modèle humain effectivement accepté, y
compris lorsqu'une synchronisation reste en attente. Une erreur ou un conflit
ne peut donc plus laisser l'écran prétendre qu'un fait humain a été enregistré.

Les modifications effectuées directement dans la fiche d'une personne ne
réécrivent plus le profil historique dans le cloud : elles reconstruisent
seulement sa copie locale d'affichage. Le contrat de propriété refuse aussi
désormais toute modification, par le domaine Profil, de la situation
professionnelle, des adresses et faits personnels durables, des informations
de transport, de garde, de lieux importants et des faits du partenaire déjà
possédés par `HumanModel`.

Le premier démarrage conserve volontairement l'ancien profil comme entrée de
migration idempotente. Les réglages, souvenirs et horaires structurés qui ont
encore leur propriétaire historique seront déplacés par lots séparés avant la
suppression physique finale de `UserProfile`.

### Progression Mémoire — premier lot sûr préparé

Le contrat de migration des anciens champs libres du profil vers la mémoire
canonique est maintenant codé et testé pour un premier groupe borné :

- habitudes ;
- préférences générales et alimentaires ;
- objectifs généraux, personnels, familiaux et professionnels ;
- priorité de vie principale.

La migration utilise des identifiants stables isolés par compte, la
déduplication sémantique et le cycle de vie officiel de la mémoire. Une valeur
différente n'écrase jamais silencieusement un souvenir existant : elle est
signalée comme conflit et l'ancienne projection reste disponible.

Les notes personnelles, administratives et budgétaires sont volontairement
exclues. Elles ne pourront rejoindre la mémoire qu'après définition d'un
contrat de confidentialité dédié.

Le raccordement automatique à la collection mémoire Firestore a été autorisé
explicitement par l'utilisatrice le 21 août 2026. Il s'exécute au chargement ou
à l'enregistrement du profil uniquement lorsque l'empreinte des champs sûrs a
changé. Une panne ne bloque jamais le profil et ne marque pas la migration
comme terminée, afin qu'elle puisse être reprise sans doublon.

Lorsqu'au moins un souvenir est créé, la section Mémoire du contexte de vie est
invalidée immédiatement. La conversation et les raisonnements suivants relisent
donc la source canonique sans imposer à l'utilisatrice de fermer ou recharger
l'application.

Progression planning : les horaires structurés de travail, d'école et
d'activité sont maintenant possédés par la personne dans `HumanModel`. Le
profil ne conserve qu'une vue temporaire pour les écrans existants. Le domaine
Profil refuse ces champs dans ses mutations génériques afin d'empêcher la
création d'une seconde source de vérité.

### Progression Réglages — registre canonique

Les préférences techniques qui étaient encore mélangées aux informations
personnelles disposent maintenant d'un propriétaire dédié, versionné et isolé
par compte : `AppSettings`.

Ce registre possède désormais :

- l'activation du calcul automatique des trajets ;
- les préférences historiques de ton, d'organisation et de niveau de
  notification ;
- la langue, le pays et le fuseau horaire choisis dans l'application.

Les réglages précis des notifications, l'autonomie d'action et la politique de
mémoire conservent chacun leur propriétaire spécialisé. Ils ne sont donc pas
dupliqués dans `AppSettings`.

Au premier chargement d'un ancien compte, les valeurs du profil historique
sont migrées une seule fois. Ensuite, le registre canonique gagne toujours sur
une ancienne copie du profil. L'écran Profil continue à recevoir une vue de
compatibilité afin que cette migration ne produise aucun changement visible.
Le domaine Profil refuse désormais d'écrire ces champs dans son ancien
document cloud.

### Étape F — unifier les décisions

- Faire partir toute décision multi-domaine d'une photographie du contexte de
  vie.
- Autoriser une lecture directe du domaine uniquement pendant la mutation et
  sa revalidation finale.
- Créer des projections bornées selon le besoin : conversation immédiate,
  semaine, préparation d'événement ou anticipation longue.

Le moteur de priorité proactif, l'anticipation de charge mentale et le parcours
de recherche de créneau utilisent désormais la production canonique du contexte
de vie. La construction d'une proposition de planning exige maintenant la liste
d'événements issue de cette même photographie : son ancien repli qui relisait
l'Agenda séparément a été fermé. Une lecture directe reste autorisée pour
enregistrer l'Event final ou modifier la durée de la Task choisie, car il s'agit
alors d'une mutation du domaine propriétaire et non d'une nouvelle décision.

Le regroupement des tâches liées à une même sortie utilise lui aussi la section
Tâches bornée de cette photographie de planning. Il ne relit plus la liste des
tâches séparément. L'ancien point d'entrée du moteur de créneaux qui pouvait
recharger directement l'Agenda a été supprimé. Ainsi, événements, routines,
responsabilités et tâches utiles à une proposition viennent de la même génération
du contexte de vie. Le domaine Tâches reste optionnel : son indisponibilité ne
doit pas empêcher une recherche de rendez-vous qui dépend seulement de l'Agenda
et des contraintes connues.

Le centre d'alertes utilise maintenant cette même photographie pour prouver les
chevauchements entre rendez-vous. Il ne recharge plus l'Agenda après la création
du contexte de vie. Les conflits Événement/Événement, Événement/Routine et les
signaux liés aux tâches reposent donc sur une génération cohérente, avec les
mêmes révisions, états de disponibilité et bornes de lecture.

### Étape G — nettoyer et vérifier les droits

- Retirer `AppDataService` après preuve de non-usage et migration éventuelle.
- Tester suppression, déconnexion, reconnexion, export et changement de compte
  pour chaque domaine.
- Vérifier qu'une donnée d'un compte ne peut jamais être lue par un autre.

Le premier nettoyage de cette étape est terminé : `AppDataService` et ses trois
anciennes clés non liées à un compte ont été supprimés. Un test d'architecture
interdit son retour. Les caches de compatibilité du profil et de l'agenda sont
liés au compte, et les domaines Tâches et Courses n'ouvrent leur cache invité
que lorsqu'aucun compte n'est connecté. Pour un compte connecté, ils chargent
leur état révisionné avec l'identifiant de ce compte.

Le parcours « Confidentialité et mes données » dispose maintenant d'un cycle
de vie réel et fermé. Une fonction serveur authentifiée et protégée par App
Check peut :

- produire une copie JSON bornée de toutes les données applicatives possédées
  sous `users/{uid}` ainsi que des informations techniques de quota du compte ;
- supprimer récursivement ces mêmes données applicatives et leur quota, sans
  supprimer le compte de connexion Firebase Auth.

L'application n'envoie jamais l'identifiant du compte au serveur : celui-ci est
déduit du jeton authentifié. Une suppression exige la saisie explicite de
`SUPPRIMER`. Les caches locaux liés au compte ne sont nettoyés qu'après la
confirmation du succès serveur ; les données invitées, globales ou appartenant
à un autre compte restent intactes. Les tests utilisent uniquement des doubles
et ne suppriment aucune donnée réelle.

Le nettoyage couvre aussi le cache borné de la liste de courses actuelle, dont
la clé historique utilise un séparateur différent des autres domaines. Sa copie
temporaire en mémoire est retirée pour le seul compte supprimé. Les courses
invitées et les caches d'un autre compte ne sont jamais touchés.

Le passage entre comptes est maintenant fermé au niveau du profil. Se connecter
à un compte existant recharge les données qui appartiennent à ce compte sans
enregistrer le profil visible avant la connexion. La fenêtre du compte est
également fermée avant la déconnexion : aucune adresse ni information de
l'ancien compte ne reste affichée pendant que l'application recharge l'espace
invité ou le compte suivant. La création d'un compte depuis une session anonyme
conserve naturellement le même identifiant Firebase ; elle ne nécessite donc
aucune copie supplémentaire du profil.

## 9. Interdictions pendant la migration

- Ne pas ajouter un nouveau champ au profil historique sans propriétaire cible.
- Ne pas créer une seconde collection pour résoudre rapidement un problème
  d'écran.
- Ne pas enregistrer une course, une tâche ou un planning dans la mémoire
  personnelle par commodité.
- Ne pas transformer automatiquement le planning d'un tiers en événement de
  l'utilisatrice.
- Ne pas faire du contexte de vie un stockage modifiable.
- Ne pas supprimer une compatibilité avant d'avoir migré les données existantes
  et vérifié la reconnexion.
- Ne pas charger toutes les données sans limite pour donner l'impression d'un
  cerveau complet ; utiliser une projection adaptée au but.

## 10. Critères avant la prochaine phase fonctionnelle

La fondation sera considérée unifiée lorsque :

- chaque concept de la table de propriété possède un seul propriétaire testé ;
- Courses et Réglages ont rejoint le contexte de vie ;
- `UserProfile` ne peut plus diverger de `HumanModel` ;
- un import ne crée que les représentations prévues et idempotentes ;
- toutes les décisions multi-domaines utilisent une photographie cohérente ;
- modifier ou supprimer une information met à jour toutes les vues sans
  doublon ;
- déconnexion et reconnexion restaurent les mêmes données ;
- les tests prouvent l'isolation entre comptes ;
- aucun document importé n'est conservé après validation ;
- l'interface peut évoluer sans déplacer la source de vérité.

Les raccordements de lecture Réglages et Courses sont désormais engagés. La
phase suivante peut réduire progressivement le profil historique, sans
changement visible pour l'utilisatrice et sans faire du contexte de vie une
nouvelle source de vérité.

Le statut du couple et ses dates sont désormais possédés uniquement par la
relation canonique dans `HumanModel`. La projection de compatibilité les remet
à disposition des anciens écrans sans les recopier sur la personne. Cette même
projection retire les personnes devenues historiques afin qu'un profil supprimé
ne puisse pas réapparaître dans la famille affichée.
