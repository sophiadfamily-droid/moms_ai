# ZELIA Memory Architecture

## Status

This document describes the implemented Memory Lifecycle Engine V1 and the
consent-aware M.1 policy. The Firestore collection remains
`users/{uid}/memories`; no migration or new collection is required.

## Phase 4A contradiction detection

Potential replacement detection is read-only for the existing memory. It
requires a valid modern semantic identity, an exact `canonicalKey`, matching
subject and context, supported revisions, direct or explicitly corrective
user evidence, and a deterministic closed-attribute value comparator. The
automatic comparators currently supported are `preferred_appointment_period`,
with the structured values `morning`, `afternoon`, and `evening`, and a
relative's `birthday`, normalized as a month-day value under a deterministic
household subject. Legacy birthday records are re-read through the same
semantic parser without being rewritten. Other attributes fail closed.

The Firestore repository performs a bounded single-field `canonicalKey` query
inside the authenticated `users/{uid}/memories` collection and applies
lifecycle and trust checks locally. This requires no new composite index. A
future server-side lifecycle filter would require a composite index on
`canonicalKey` and `lifecycleState`; it is intentionally neither configured
nor deployed in Phase 4A.

Detection creates the new `proposed` document and a separately addressable,
deterministically identified pending replacement action in one transaction.
That transaction reads and writes only these two new workflow documents; it
never changes the existing memory. The implemented replacement execution then
requires explicit acceptance and atomically marks the previous memory as
superseded, confirms the proposed memory, and closes the durable action.
Pending replacement proposals are not shown as additional retained memories
in the consumer library.

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
- `askEveryTime`: an inferred eligible proposal stays proposed until confirmed.
  A clear user directive such as `souviens-toi`, `rappelle-toi`, `retiens` or
  `mémorise` is itself the fresh confirmation for an ordinary, attributable,
  unambiguous fact and does not trigger a redundant second question;
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

Before this policy is evaluated, `MemoryEvidenceClassifier` deterministically
qualifies the current user message. Provenance and evidence are deliberately
separate: `source: explicit_user_message` only records where a candidate came
from and is never sufficient evidence for automatic confirmation. The closed
qualification records a primary classification, minimal subject attribution,
risk codes, and whether immediate confirmation is allowed. Only a direct,
declarative, present or durable statement with an attributable subject and no
ambiguity, hypothesis, conditional, quotation, unresolved third party,
question, past-only state, or temporary-only state may enter the policy's
explicit-evidence path. Assistant candidates always remain proposed.

An explicit save directive is recorded separately from evidence. It may
activate the eligible proposal immediately because the directive already
expresses the user's decision. It never bypasses pause, health consent,
high-sensitivity rejection, structured-domain ownership, duplicate handling,
or contradiction/replacement safeguards.

Qualification is fail-closed. The deterministic order is: quotation, unresolved
third party or question; bounded correction and its current clause; hypothesis,
conditional or uncertainty; temporary state; past-only state; negated positive
claim; explicit durable negative constraint; positively recognized direct
statement; then `unknown`. First-person grammar alone never proves a direct
statement, and the policy receives explicit evidence only when this classifier
allows immediate confirmation.

Clear corrections such as “finalement” or “en fait” carry `isCorrection` and
the `correction` evidence classification. For bounded past-to-present forms,
only the current clause is proposed as the new memory. An uncertain current
clause retains `isCorrection` but remains proposed. This metadata does not
supersede, delete, or rewrite an earlier memory; contradiction identity and
replacement remain a separate future phase. Evidence diagnostics contain
closed reason codes only, never the message text.

## Semantic identity V1

Every newly created proposal receives a `MemorySemanticIdentity` independently
from its lifecycle and evidence qualification. The identity contains a closed
domain and attribute, a subject scope, an optional stable subject identifier,
an optional closed context type plus opaque entity fingerprint, a schema
version, and a deterministic `canonicalKey`. The remembered value remains
separate as `semanticValue`.

The key format is
`v1|domain|attribute|subject_scope|subject_fingerprint|context_type|context_fingerprint`.
It contains neither the remembered value, the original sentence, nor a raw
person, household, residence, or context identifier. Exact UTF-8 identifiers
are fingerprinted as SHA-256 over
`zelia-memory-subject-v1|scope|identifier` (or the corresponding
`zelia-memory-context-v1` namespace), without lower-casing or punctuation
rewrites. Thus distinct opaque identifiers remain distinct, while morning and
afternoon appointment preferences share an identity and retain different
values.

First-person evidence maps to `authenticated_user`; a previously resolved
entity contributes only its fingerprint. Structured entity, household, and
residence scopes require a non-empty stable identifier; otherwise they become
unknown. No primary household or residence is inferred. Unknown subjects
receive a deterministic fingerprint derived from the already stable proposal
identifier and
`eligibleForAutomaticContradiction=false`, so two unresolved people cannot be
treated as identical. Generic fallback attributes also remain ineligible; only
a closed, coherent domain/attribute/context combination can be eligible.
Context types are closed and optional context entity identifiers are
fingerprinted, so free text never enters the key.

Modern identities are read fail-closed: schema version, enums, field types,
fingerprints, component coherence, recalculated key, and recalculated
eligibility must all agree. The reader distinguishes a valid identity, an
absent legacy identity, and an invalid modern identity. Absence remains
backward-compatible; an incomplete or forged modern identity is never
rehabilitated. Phase 3 only writes and validates this additive identity
metadata. It does not detect contradictions, replace memories, or perform
supersession.

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

Legacy `text`, `normalizedText`, `category`, `importance`, `createdAt`,
`updatedAt`, and `source` remain unchanged and readable. Unknown historical
fields remain in immutable legacy metadata. Lifecycle, confirmation, evidence
and sensitivity markers are validated as a closed coherent set when present.

`MemoryContext` schema v1 adapts historical records without rewriting them. It
keeps stable identifiers, lifecycle, confirmation, dates, provenance,
sensitivity, explicit health classification, and optional structured-domain
references. Missing dates remain absent; ambiguous legacy provenance remains
unconfirmed; unknown fields stay in the legacy reader metadata. No old key or
record is deleted.

The old `MemoryService.saveMemory` writer persisted `source: "chat"` but no
field proving whether the text was a direct user statement or an assistant
inference. Records with this exact provenance are therefore classified
`legacyQuarantined` at read time. They remain intact in Firestore but are not
sent to Conversation or Planning and cannot create a `blocked_period`. A
future explicit confirmation or a controlled provenance migration is required
before they can be consumed; this compatibility reader performs no migration.

Persisted sensitivity markers take precedence over lexical classification.
Unknown or contradictory markers fail closed. Credentials, secret codes,
access tokens, keys and payment-card data are never consumable as
personalizing memory. Other sensitive legacy records remain quarantined
because the historical document does not carry sufficient consent evidence.

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

General Memory reasoning now consumes `MemoryReasoningContext`, derived only
from the canonical LC.1 Memory section and carrying its source generation,
revision, freshness and closed warning codes. It does not reread
`MemoryService` or construct a second Life Context. Confirmed active records
are eligible; proposed, rejected, superseded, expired, ambiguous and
explicit-health records remain excluded.

Planning excludes free Memory. Historical memories explicitly typed as
Routine and accepted by the central consumption policy may pass through the
narrow `MemoryPlanningCompatibilityService.buildFromLifeContext` bridge.
Quarantined routines, including ambiguous `source: "chat"` records, never
produce blocked periods. Free preferences, facts, habits, or constraints are
never interpreted as Planning rules. The former profile-and-repository reader
remains an explicit legacy compatibility entry point, not the production Smart
Planning source.

`MemoryProjectionBackendSerializer` is the only Memory-to-backend boundary. It
accepts either the filtered Conversation projection or, during the controlled
transition, its already-filtered historical selection. It emits bounded maps
using the established `text`, `category`, `importance`, and creation metadata
contract; the LC.3 path also carries confirmation and minimal source. Neither
the full repository, `MemoryContext`, Life Context snapshot/graph, profile, nor
source conversation is serialized. `memoryReasoning` remains a separate
bounded compatibility field and does not duplicate the Memory repository.

## Conversational confirmation workflow

V1-A.1 adds an independent account-scoped autonomy guard. It never replaces
`MemoryPolicy`: the effective result is the most restrictive of autonomy mode,
memory mode, health consent and the existing lifecycle confirmation. An
inferred candidate in `normal + askEveryTime` still requires confirmation,
`suggestions + automatic` confirms, and `paused + automatic` blocks the
mutation without deleting its proposal. A clear explicit save directive is
already the user's fresh confirmation for an eligible ordinary memory; the
conversation therefore activates it and acknowledges the result without
asking `oui` a second time.

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
ni les conflits complets, ni les reçus ne sont projetés. Depuis C.2,
Conversation sérialise cette unique projection LC.3 dans l’enveloppe bornée
`conversation.transport.v1`. Le champ de compatibilité `memoryReasoning` reste
vide et aucun `MemoryContext` complet n’est transporté. La redaction Flutter et
Functions refuse santé, médical, tombstones, archives, suppressions, conflits
et données inconnues. Planning continue d’exclure toute mémoire libre.

## M.3 — Bibliothèque et contrôle visible

`MemoryLibraryService` est l’unique frontière d’application de la bibliothèque.
Les écrans ne connaissent ni Firestore, ni SharedPreferences, ni la file M.2.
La façade charge l’état paginé et borné, produit les sections actif,
à-confirmer, pending, historique et conflit, explique les faits par des règles
fermées, puis transforme toute action en mutation M.2 avec `expectedRevision`
et `mutationId`.

L’écran « Ce que Zélia retient », accessible depuis les réglages mémoire,
propose des filtres canoniques, un détail sans identifiant technique, une
provenance en français, l’état de confirmation et de synchronisation, ainsi
qu’un historique produit limité à 50 événements. Les explications sont
déterministes et n’appellent ni OpenAI ni un service de diagnostic.

Une correction conserve l’identifiant, la provenance initiale et ajoute un
événement de correction. Elle refuse le vide, une période incohérente, une
politique santé insuffisante et toute référence possédée par un domaine
structuré. Confirmation, rejet et report restent distincts : le report
n’affirme aucune écriture, le rejet reste inactif et la confirmation n’est
annoncée qu’après le résultat de la synchronisation.

L’archivage est un état révisionné, historique et restaurable. Une suppression
individuelle produit un tombstone révisionné : le contenu est remplacé par un
marqueur neutre, l’historique est réduit à la preuve technique minimale, et
aucun delete Firestore n’est effectué. Un tombstone ne peut pas être réactivé.
Une archive santé ne peut être restaurée que si le consentement santé actuel
l’autorise; la suppression reste toujours possible.

La suppression globale exige la saisie exacte « SUPPRIMER MA MÉMOIRE ». Elle
parcourt uniquement le domaine Memory par pages de 20, est reprenable par
curseur et s’arrête en état pending hors ligne sans annoncer un succès cloud.
Les références structurées et les mémoires legacy Routine sont archivées
plutôt que supprimées afin de ne créer aucun trou silencieux. Aucun compte,
profil, HumanModel, Identity, Event, Task ou Routine n’est touché.

Les conflits M.2 sont affichés sans révision technique. La personne peut garder
la version distante, abandonner sa mutation ou recharger; aucun merge de texte
n’est proposé. Life Context filtre les tombstones dès l’adaptateur, les
archives ne sont pas consommables, Conversation reconstruit sa prochaine
projection et Planning continue d’exclure toute mémoire libre.

## Deliberately deferred

- general contradiction and entity-resolution engines;
- probabilistic or model-based similarity;
- restoration workflow;
- complete memory-management UI;
- physical deletion and global Firestore migration;
- relations, priorities, consequences, and proactive anticipation.

# Confirmation d’action A.3

Les confirmations exécutables de Memory utilisent désormais le contrat
`ActionConfirmation` commun tout en laissant `MemoryPolicy`, le consentement
santé et le cycle M.1–M.3 prioritaires. Des exigences identiques peuvent
partager une présentation ; une autorisation santé de portée distincte reste
séparée. Toute confirmation possède une empreinte, une session et une
expiration, puis MemoryPolicy et la policy santé sont relues avant mutation.
Une confirmation ne constitue jamais un résultat d’enregistrement.
