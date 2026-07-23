# ZELIA Memory Architecture

## Status

This document describes the implemented Memory Lifecycle Engine V1 and the
consent-aware M.1 policy. The Firestore collection remains
`users/{uid}/memories`; no migration or new collection is required.

## Ownership

Memory owns durable preferences, declared habits, goals, constraints,
instructions, and personal facts that have no better structured owner. Event,
Task, Routine, HumanModel, Identity, households, residences, relationships,
responsibilities, and Planning remain authoritative for their own facts. A
memory may retain a bounded technical reference to one of those facts but
cannot replace or overwrite it. `UserProfile` remains a legacy compatibility
view and is never copied wholesale into memory.

Memory and Life Context are also distinct: Memory retains information through
time; Life Context reconstructs the facts needed by a consumer. Memory is one
read-only Life Context source, not the owner of the aggregate context.

## Consent policy

`MemoryPolicy` schema v1 is isolated by authenticated `accountScopeId`.
Missing policy means `askEveryTime` and health `disabled`; absence is never
automatic consent.

General modes:

- `automatic`: only an explicit, ordinary, sufficiently trusted, eligible,
  non-duplicate proposal outside a structured domain may be saved;
- `askEveryTime`: an eligible proposal stays proposed until confirmed;
- `paused`: no new proposal or write is created. Existing records remain
  readable and untouched.

Health modes are independent:

- `disabled`: reject every new explicit health memory;
- `askEveryTime`: require confirmation for each item;
- `enabled`: permitted only after explicit health consent.

General automatic mode cannot enable health. No medical condition is inferred,
and this setting concerns memorization rather than medical advice or
diagnosis.

`MemoryPolicyEngine` is pure and deterministic. It returns a closed decision:
automatic save, confirmation required, duplicate, structured-domain ownership,
contradiction, sensitive/highly-sensitive rejection, health-consent rejection,
pause, or invalid proposal. It neither parses free conversation nor reads,
writes, or calls a model.

All transitions retain existing memories and pending proposals, approve
nothing implicitly, change no Routine or other domain, and perform no
retroactive ingestion after a pause. The minimal profile settings are stored
locally under `memory_policy_v1:{accountScopeId}`. Cross-device policy
revisions belong to M.2.

## Three independent dimensions

- `LifeMemorySemanticType` describes meaning: fact, preference, routine,
  constraint, goal, decision, temporary, relationship, or unknown.
- `MemoryConfirmationStatus` describes explicit evidence of confirmation.
- `MemoryLifecycleState` describes operational state: proposed, confirmed,
  rejected, active, superseded, obsolete, deleted, or expired.

These dimensions must not be inferred from one another except at the legacy
read boundary, where explicit stored lifecycle fields may provide evidence for
the compatible confirmation projection. Missing historical fields always fall
back to `proposed` and `unconfirmed`.

## State machine

Allowed V1 transitions are:

```text
proposed  -> confirmed | rejected | deleted
confirmed -> active | deleted
active    -> superseded | obsolete | deleted | expired
obsolete  -> deleted
expired   -> deleted
superseded -> deleted
rejected  -> (none)
deleted   -> (none)
```

`restore` is represented in the action vocabulary but deliberately refused in
V1. Restoration needs a product-level correction and consent workflow before
it can safely reactivate rejected, obsolete, expired, superseded, or deleted
knowledge.

## Responsibilities

`MemoryLifecycleEngine` is pure and deterministic. It validates proposals and
commands, detects exact typed duplicates and conservative same-category
conflicts, applies the explicit state machine, and returns decisions plus
proposed mutations. It never calls AI, Firebase, clocks, or persistence.

`MemoryLifecycleRepository` owns persistence. Its Firestore implementation
writes optional additive lifecycle fields and audit records. It does not make
business decisions. Candidate lookup uses bounded exact-text and category
queries instead of loading the user's complete memory history. A fake can
replace the repository in tests.

`HistoricalMemoryContextProjection` remains the compatibility reader. It
preserves unknown fields, never invents confidence, and never marks a document
confirmed without an explicit stored confirmation or lifecycle state.

## Proposals and confirmation

AI-produced memory output and conversation detections are candidates. The live
boundary persists them as `proposed` and `unconfirmed`, with a stable document
identifier and minimal lifecycle record. Sensitive information always requires
explicit confirmation. A profile conflict produces no mutation and keeps the
explicit profile authoritative.

## Replacement and deletion

A replacement never physically deletes the previous memory. The old memory is
marked `superseded` with `replacedByMemoryId`; the new memory records
`supersedesMemoryId`. Without an explicit user actor, the engine returns a
confirmation request and no mutation.

Deletion is logical. The state becomes `deleted`, `deletedAt` is stored, and a
minimal record preserves actor, date, source, reason, previous state, and new
state. Repeated commands are idempotent.

## Temporary knowledge and expiration

Temporary knowledge preserves supplied `validFrom`, `validUntil`, and
`expiresAt`. No end date is invented. An ambiguous temporary proposal requests
clarification. Expiration uses only the reference date injected into the
engine.

## Historical compatibility

All lifecycle fields are optional. Legacy `text`, `normalizedText`, `category`,
`importance`, `createdAt`, `updatedAt`, and `source` remain unchanged and
readable. Unknown historical fields remain in immutable legacy metadata.
Existing routines therefore retain their creation anchors and planning
behavior.

`MemoryContext` schema v1 adapts historical records without rewriting them. It
keeps stable identifiers, lifecycle, confirmation, dates, provenance,
sensitivity, explicit health classification, and optional structured-domain
references. Missing dates remain absent; ambiguous legacy provenance remains
unconfirmed; unknown fields stay in the legacy reader metadata. No old key or
record is deleted.

The LC.1 `MemoryLifeContextAdapter` reads this source through an account-bound
service and returns a typed section distinguishing available, empty, stale,
unavailable, corrupted, account-mismatched, paused, and unconfigured policy
states. The broader read is still bounded only at projection time; pagination
or server-side relevance is deferred to M.2.

## Consumer projections

LC.3 Conversation includes only active, non-rejected, non-expired,
policy-authorized memories under a deterministic section budget. Explicit
health and memories already represented by a structured domain are excluded.
Text is normalized and bounded. Confirmation and minimal provenance remain
visible to the typed consumer.

Planning excludes the Memory domain. For backward compatibility only,
historical memories explicitly typed as Routine may still pass through
`MemoryPlanningCompatibilityService` so existing recurrence anchors and
blocked periods keep working until their Routine migration. Free preferences,
facts, habits, or constraints are never interpreted as Planning rules.

`MemoryProjectionBackendSerializer` is the only Memory-to-backend boundary. It
accepts either the filtered Conversation projection or, during the controlled
transition, its already-filtered historical selection. It emits bounded maps
using the established `text`, `category`, `importance`, and creation metadata
contract; the LC.3 path also carries confirmation and minimal source. Neither
the full repository, `MemoryContext`, Life Context snapshot/graph, profile, nor
source conversation is serialized. `memoryReasoning` remains a separate
bounded compatibility field and does not duplicate the Memory repository.

## Conversational confirmation workflow

`ConversationCoordinator` is the application boundary for a memory proposal.
It keeps a typed pending action containing only the proposal identifier, the
expected lifecycle action, and its creation date. The proposal is reloaded by
identifier before every decision; its text and internal metadata are not
duplicated in conversation state.

Existing event and planning confirmations retain priority. The chat screen
routes a reply to the memory workflow only after those pending workflows have
declined it, so words such as “oui”, “non”, or “oublie” cannot select a memory
without a typed memory pending action.

The deterministic conversation classifier recognizes a deliberately small set
of normalized French positive and negative answers. Mixed or unknown signals
are ambiguous and cause a short clarification without mutation. User approval
executes `proposed -> confirmed -> active` through `MemoryLifecycleEngine` and
applies both returned mutations through `MemoryLifecycleRepository`. Rejection
executes `proposed -> rejected`. No conversation component writes lifecycle
fields directly.

Terminal, missing, and expired proposals return a safe unavailable response.
Repeated handling is idempotent. Repository failures retain the pending action,
do not claim success, and allow a retry. Proposal persistence failure remains
non-blocking for the broader conversation.

The pending action follows the current in-memory conversation-state mechanism.
An application restart therefore clears it safely instead of guessing the
target of a late reply. Durable pending confirmation recovery, multiple queued
memory proposals, localization resources, and a complete memory-management UI
remain outside V1.

## M.2 — Révisions, hors ligne et continuité multiappareil

Firestore est la référence partagée validée. La politique canonique réside
dans `users/{uid}/private/memoryPolicy`; les souvenirs restent dans
`users/{uid}/memories/{memoryId}` afin de préserver la collection historique.
Chaque document canonique porte un schéma v1, un `accountScopeId` égal au
propriétaire du chemin, une révision monotone, un `lastMutationId`, des
timestamps serveur et les statuts fermés définis par M.1. Les mises à jour sont
transactionnelles et exigent `expectedRevision`; elles effectuent exactement
N vers N+1. Une suppression physique directe est refusée.

Le stockage local versionné conserve, par compte, le dernier état valide, la
politique et ses révisions, jusqu’à 500 souvenirs, 50 mutations, 25 conflits
et 100 reçus d’idempotence, ainsi qu’une sauvegarde précédente. La priorité de
lecture est : cloud validé, cache local validé, adaptateur legacy, absence
explicite. Une version future ou une corruption n’est jamais transformée en
liste vide. Les anciennes clés et les anciens documents ne sont ni supprimés
ni réécrits aveuglément.

Une mutation structurée contient un identifiant idempotent, la cible, son
`expectedRevision`, le type fermé, la politique observée, la classification
santé, la tentative et la prochaine échéance. La file est ordonnée et bornée.
Seules des mises à jour locales compatibles d’une même cible peuvent être
coalescées; aucun texte, contradiction, compte ou catégorie santé/générale
n’est fusionné. Les retries sont bornés à cinq tentatives avec backoff
exponentiel plafonné à cinq minutes et horloge injectable.

La politique est relue avant l’envoi. Une pause bloque toute nouvelle création;
la désactivation santé bloque les mutations santé; le passage à un mode plus
permissif ne confirme jamais rétroactivement une proposition. Les conflits de
révision, contenu, confirmation, politique, expiration, suppression, domaine
structuré, scope, version et corruption sont explicites et ne sont jamais
présentés comme synchronisés. La résolution technique permet de garder le
distant, abandonner la mutation, demander une décision ou réessayer une seule
fois contre la dernière révision après revalidation complète. Aucun merge de
texte libre et aucun last-write-wins ne sont autorisés.

`validUntil` décrit la validité, `expiresAt` le seuil d’expiration,
`expired` le cycle de vie, et un tombstone éventuel une suppression logique :
ces notions restent distinctes. L’expiration est évaluée à la lecture et peut
être matérialisée par une mutation idempotente; elle n’efface pas l’historique
et une ancienne mutation ne la réactive pas.

Le bootstrap restaure politique et pages mémoire (100 documents par page,
500 au maximum), préserve la file locale, traite les expirations et isole tout
changement de compte. Un nouvel appareil ou une réinstallation reconnectée au
même compte reprend les identifiants cloud. La liaison d’un compte anonyme
préserve ce contrat parce que Firebase conserve le même UID. Hors ligne, le
dernier état local valide reste lisible sans prétendre être synchronisé.

Life Context expose seulement les compteurs bornés, la fraîcheur, la révision
de politique, l’état de synchronisation et la présence de conflits; ni la file,
ni les conflits complets, ni les reçus ne sont projetés. Conversation continue
d’utiliser la projection M.1/LC.3 et Planning continue d’exclure toute mémoire
libre. La bibliothèque, la correction et les suppressions visibles restent
réservées à M.3.

## Deliberately deferred

- complete library, correction, individual deletion, and detailed explanation
  UI (M.3);
- general contradiction and entity-resolution engines;
- probabilistic or model-based similarity;
- restoration workflow;
- complete memory-management UI;
- physical deletion and global Firestore migration;
- relations, priorities, consequences, and proactive anticipation.
