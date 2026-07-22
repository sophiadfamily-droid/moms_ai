# Identity Engine V1

## Status

Engineering specification with Phase 1 implemented. The repository contains
stable record-identity primitives and a pure deterministic entity-resolution
domain. Persistence and application integrations remain planned.

### Implementation status

**Implemented in Phase 1:** closed domain enums, immutable `LifeEntity`, typed
aliases/references/candidates/relations/results, deterministic normalization,
bounded pure resolution, one-level merge redirection, explainable signals, and
unit/architecture tests.

**Implemented in Phase 2:** framework-independent repository contract, explicit
account scope, bounded typed candidate queries, deterministic result ordering,
additive UTC serialization, defensive historical reads, and an in-memory fake
covered by a reusable contract suite.

**Implemented in Phase 3A:** a framework-independent, read-only application
service validates scoped resolution requests, performs bounded repository
lookups, attaches only caller-supplied evidence, invokes the deterministic
domain engine, and maps failures to safe typed results.

**Implemented in Phase 3B:** controlled clarification for existing ambiguous
identities, with a typed pending state, deterministic numbered or exact-label
selection, stable entity IDs, cancellation, and a fifteen-minute expiration.
The LLM never selects a candidate and no business action resumes automatically.

**Implemented in Phase 3C:** a resolved existing person identity can be attached
temporarily to an in-memory conversation draft for the single
`eventParticipant` role. Ambiguous resolutions retain a minimal typed
continuation through clarification. Selection enriches the draft binding only;
it never creates the event or resumes an irreversible action automatically.

**Implemented in Phase 3D-A:** the pure `PersistedIdentityLink` value contract
and its defensive, framework-independent map codec define how a resolved
Identity reference may be represented in a future business object. The
contract stores only entity ID, entity type, and schema version; corrupt or
future persisted values produce typed, non-sensitive read results.

**Implemented in Phase 4B:** a dormant, explicitly scoped Firestore read
boundary supports bounded lookup by ID, canonical normalized label, and the
derived `aliasComparisonKeys` index under
`users/{userId}/identities/{entityId}`. It validates every document through
the canonical Identity codec, preserves the twenty-candidate limit and
deterministic ordering, and maps Firestore failures to safe repository codes.
Identity writes are explicitly denied by Firestore rules and absent from the
concrete repository. Emulator and rules tests use a dedicated non-production
project guard.

**Implemented in Phase 4C:** a separate dormant `IdentityWriteRepository`
defines explicit create-only, revision-checked update, and transactional logical
deletion operations. The Firestore implementation injects its client, keeps
account scope explicit, initializes revision one, increments exactly once, and
rejects stale revisions, immutable-field changes, merge transitions, corrupt
documents, and physical deletion. Firestore rules validate the version-one
shape and repeat the ownership, revision, immutability, status, and hard-delete
guards. Emulator coverage includes concurrent writers using the same expected
revision.

**Implemented in Phase 4D:** a controlled application-level creation workflow
can turn an explicit structured `notFound` result into a bounded, expiring
conversation proposal. Only an explicit positive answer triggers a fresh exact
ID and label/alias recheck followed by `IdentityWriteRepository.create`.
Cancellation, ambiguity, expiration, duplicates, and repository failures write
nothing and never produce a success message.

**Implemented in Phase 4E:** the existing `eventParticipant` action-binding
entry point can route a typed resolution result into the confirmed creation
workflow. Resolved identities still attach directly, ambiguity still uses the
existing clarification, and only `notFound` with an explicit compatible
creation request can create a pending proposal. A successful creation attaches
the new stable ID to the in-memory draft binding without executing the event.

**Implemented in Phase 4F-A:** event actions may carry one optional, closed,
typed person participant from the strict backend schema through the client
guard and temporary conversation draft. The server retains it only when its
bounded label occurs literally in the original user message after conservative
case, accent, apostrophe, punctuation, and whitespace normalization. Pronouns,
closed relational expressions, invalid shapes, non-event uses, and unproven
labels are removed without rejecting the otherwise valid event action.

**Implemented in Phase 4F:** the production composition root now injects the
scoped Firestore Identity read/write boundaries into the existing application,
clarification, creation, binding, and conversation services. Only a validated
typed event participant can start resolution, after the event draft has passed
its normal information collection and initial conflict checks. The immutable
draft is suspended in the coordinator, then resumed at the distinct event
confirmation after direct resolution, explicit clarification, or confirmed
creation.

The Identity Engine is not applied to every chat message. Phases 3A through 3C
create no identity or proposal, perform no Identity save, and have no
concrete Firestore repository or production-persisted Identity data. Phase
3D-A is a dormant contract only: no event, task, shopping, conversation, or
backend model uses it; it performs no Firestore write and creates no active
business link. No index, migration, profile seeding, location binding, task
binding, or shopping binding is implemented.

Phase 4B is not composed into the production application and creates no
Firestore data. It provides no creation, update, deletion, merge, migration,
or backfill workflow. No persistent Identity source of truth is active until a
later explicitly controlled write phase is implemented and deployed.

Phase 4C remains infrastructure only. No production composition, conversational
creation decision, user confirmation, profile projection, relation, merge,
business-object link, migration, backfill, or deployment is included. The
rules and transactional repository are exercised only against the guarded
local emulator; application code cannot currently invoke Identity writes.

Phase 4D reuses the single typed pending-action state in
`ConversationCoordinator`, but remains explicitly injectable and absent from
the production composition root and screens. It does not infer proposals from
free text or backend/LLM output, create aliases or relations, modify existing
identities, merge, delete, migrate, backfill, or connect identities to business
models. A caller must first provide a validated structured request and a typed
`notFound` resolution result.

Phase 4E is limited to the explicitly invoked in-memory event-participant
binding API. It is not composed into the UI or global message flow and does not
inspect backend/LLM output or free conversation for names. Missing, mismatched,
relational, pronominal, explicit-ID, unknown-type, empty-label, or unknown-source
creation data cannot start a proposal. Tasks, shopping, memory, profile, and
all persistent business links remain excluded.

Phase 4F-A only establishes transport provenance. Literal occurrence proves
neither legal identity nor semantic intent: it deliberately does not resolve,
clarify, create, or persist an Identity. The participant remains outside
`EventModel` and Firestore, Identity services remain absent from production
composition, and the existing event confirmation behavior is unchanged.

Phase 4F activates only the single `eventParticipant` path. Identity refusal,
expiration, invalid scope, or repository failure never confirms or creates the
event. Identity confirmation and event confirmation remain separate user
decisions.

**Implemented in Phase 4G:** after the distinct event confirmation, the
coordinator revalidates the attached Identity in the explicit account scope.
Only an active person is persisted directly; inactive and deleted identities
block the event write. A merged identity is followed through a bounded,
cycle-safe chain and only its validated active target may be persisted. The
optional `participantIdentity` event field contains only `entityId`,
`entityType`, `schemaVersion`, the closed `participant` role, and the matching
`accountScopeId`. Historical events without the field remain valid; malformed
links are ignored defensively on read. Firestore rules validate the closed
shape and same-account scope. Existence and current status remain application
checks because event persistence uses collection batch rewrites. Tasks,
shopping, memory, profile, planning semantics, and backend contracts remain
unchanged; there is no migration, backfill, relation, push, or deployment.

**Outside V1:** fuzzy, phonetic, embedding, or LLM matching; global identities;
automatic merges; inferred sensitive relationships; and Knowledge Graph logic.

## Mission

Identity Engine V1 creates, retrieves, compares, and resolves stable identities
from structured or textual references. It turns mutable labels into references
to account-owned entities while preserving ambiguity, provenance, historical
text, and user control.

The engine identifies nodes. It does not own the relationships between nodes,
their scheduling rules, their memory lifecycle, or the actions performed on
their behalf.

## Verified current state

### Stable record identity foundation

`lib/core/identity/` contains four small, pure components:

- `EntityIdGenerator` abstracts ID creation;
- `UuidV7EntityIdGenerator` creates UUID v7 values without `/`;
- `EntityIdentity.isValid` accepts non-blank identifiers;
- `EntityMatcher<T>` gives valid IDs precedence and otherwise delegates to a
  domain-specific legacy comparator.

These components are tested and used in production by `EventService`,
`TaskService`, and `ShoppingService`. Their models have optional `id` fields.
Creation assigns UUID v7 values, Firestore document IDs are injected when
reading, and historical records without IDs retain domain-specific comparison
fallbacks. Cloud services use authenticated paths below `users/{uid}`.

This foundation solves record continuity for events, tasks, and shopping items.
Phase 1 now defines the pure semantic entity domain alongside it, without a
repository or application integration.

### Structured profile and Life Context

`UserProfile` represents the user, partner, children, schedules, activities,
health contacts, places, mobility, vehicles, and pets. Most identity-bearing
values are strings. `ChildProfile` has no stable identifier. Children are
associated with routines by list position and repeated first name.

`LifeContextSnapshot` projects profile data into `IdentityContext`,
`HouseholdContext`, and related contexts with provenance. It remains a
calculated projection. `HouseholdMemberContext`, `ChildRoutineContext`,
`LifeContextActivity`, `PlaceContext`, and `MobilityContext` still carry labels
or free text rather than entity IDs.

The profile is the strongest current structured source for the user, partner,
and children. It is not an entity registry and does not expose durable IDs for
those people.

### Actions, conversation, memory, and planning

The backend action schema contains titles and textual departure/arrival
contexts, but no subject, participant, assignee, recipient, place entity, or
organization identifier. The LLM receives the structured profile and may
interpret references in generated text. Client validation verifies action
shape, not entity resolution.

Memory records have stable memory IDs and provenance, but their content remains
text. They do not contain typed entity references. Backend memory relationship
keywords are categorization hints, not a resolver.

Planning uses strings such as `home`, `work`, `school`, `previous_event`, and
`unknown` for travel context. Event titles, task titles, activity locations,
school names, doctors, important places, vehicle descriptions, and pet
descriptions remain text. No deterministic pronoun or relational-reference
resolver exists.

### Resolution behavior today

| Reference | Current behavior |
|---|---|
| explicit event/task/shopping ID | Deterministic record matching |
| profile first name, partner name, child name | Supplied to Life Context and the LLM as text |
| `mon enfant` with one or several children | No deterministic selection rule; interpretation is delegated to prompt context |
| `mon conjoint` | Profile text may help the LLM; no entity result is produced |
| doctor, school, work, home | Free text or coarse vocabulary, not entity identity |
| `cette activité`, `le même lieu` | No stable cross-message identity contract |
| `elle`, `lui`, `eux` | No deterministic pronoun resolution; unsafe without explicit conversational context |

The system therefore may produce plausible language, but it cannot prove which
person or place was selected. With several equivalent candidates it has no
typed ambiguity result.

## Existing components classification

### Functional and used

- UUID v7 generation for new events, tasks, and shopping items;
- ID-first matching with legacy fallback;
- local/Firestore round-trip of those record IDs;
- UID-owned Firestore paths and ownership rules;
- typed profile/Life Context projections with provenance;
- bounded memory selection and explicit memory lifecycle.

### Partial or prototype foundations

- `lib/core/identity/` is reusable infrastructure but has no entity domain;
- `IdentityContext` describes profile facts, not entity identity;
- event departure/arrival contexts are a closed-ish string convention without
  place records;
- `parentRecurringId` relates occurrences to a series, but is a calendar-series
  link, not an Identity Engine relation.

### Absent

- entity registry and repository;
- entity type/status/source models;
- aliases and alias lifecycle;
- textual/structured references;
- deterministic candidate lookup and resolution;
- ambiguity/confirmation contract;
- entity IDs on profile members, locations, events, tasks, routines, or memory
  references;
- merge, logical deletion, correction, export, and audit workflows for entities.

No current identity-domain component is orphaned: the four foundation files are
exercised directly or by architecture tests. The misleading overlap is naming:
record identity, user authentication identity, profile identity context, and
future semantic entity identity are separate concepts.

## Domain boundary

### Responsibilities

Identity Engine V1 may:

- allocate a stable account-scoped entity ID;
- validate and normalize an entity type;
- create and update canonical labels;
- retain explicitly authorized aliases with provenance and lifecycle;
- compare typed references;
- retrieve bounded candidates;
- resolve exact deterministic evidence;
- return ambiguity or required confirmation;
- expose explainable confidence and match signals;
- preserve legacy text alongside optional entity IDs;
- propose a safe alias addition or merge operation without applying it
  implicitly.

### Out of scope

It does not:

- plan, prioritize, schedule, notify, or execute actions;
- persist conversational memory by itself;
- infer family, employment, ownership, or medical relationships silently;
- implement the Knowledge Graph;
- resolve arbitrary natural language using OpenAI;
- depend on Flutter UI, Firebase, clocks, or global mutable state in its pure
  domain layer;
- make an entity global or correlate people across accounts;
- merge entities from fuzzy similarity alone;
- choose the first child, contact, or place when several candidates match.

## Proposed domain models

All domain models are immutable and null-safe. Exposed lists and maps are deeply
unmodifiable. Domain models contain no Firestore types, UI types, local photo
paths, raw authentication tokens, or generated model reasoning.

### Enumerations

```text
EntityType
  person | place | organization | household | group | activity |
  vehicle | pet | product | unknown

EntityStatus
  active | inactive | merged | deleted

EntitySourceType
  profile | user | memory | conversation | imported | historical

EntityAliasKind
  explicit | learned | temporary

EntityReferenceKind
  id | label | alias | relationalExpression | pronoun | genericLabel

EntityResolutionStatus
  resolved | ambiguous | notFound | needsConfirmation | invalid

EntityResolutionConfidence
  exact | strong | insufficient

EntityMatchSignal
  exactId | exactCanonicalLabel | exactAlias | compatibleType |
  accountScope | householdScope | explicitRelation | explicitConversationTarget |
  userProvided | conflictingAlias | multipleEquivalentCandidates |
  deletedCandidate | incompatibleType
```

`unknown` is retained for compatibility at input boundaries, but creation of a
durable entity with type `unknown` requires confirmation or later enrichment.

### `EntityIdentity`

The existing static ID validator should be renamed or evolved carefully because
its public name currently denotes only validity. The future aggregate should
use a non-conflicting name during migration, for example `LifeEntity`, unless a
reviewed rename preserves all callers.

Proposed fields:

```text
id: String                         required, non-blank, immutable
scopeId: String                    required at repository boundary, never global
type: EntityType                   required
canonicalLabel: String             required and non-blank for active entities
normalizedLabel: String            required, deterministically derived
aliases: List<EntityAlias>         immutable
status: EntityStatus               required
source: EntityProvenance           required
createdAt: DateTime                required
updatedAt: DateTime                required, not before createdAt
mergedIntoEntityId: String?        only when status is merged
metadata: Map<String, Object?>     allowlisted, immutable, minimal
```

Confidence is not stored as an unexplained property of an entity. Verification
evidence belongs in provenance; confidence belongs to a particular resolution.

Forbidden metadata includes secrets, local file paths, full conversation
transcripts, raw medical notes, inferred sensitive relations, and arbitrary
backend maps.

### `EntityAlias`

```text
id: String
value: String
normalizedValue: String
kind: EntityAliasKind
source: EntityProvenance
createdAt: DateTime
validUntil: DateTime?
status: active | removed | expired
```

Explicit aliases come directly from the user or verified profile. Learned
aliases remain unverified until confirmed. Temporary aliases require an
explicit validity window. Removing an alias does not delete the entity.

Relational expressions (`mon enfant`), pronouns (`elle`) and generic role labels
(`le médecin`) are references, not durable aliases by default.

### `EntityReference`

```text
rawText: String?
normalizedText: String?
entityId: String?
expectedType: EntityType?
kind: EntityReferenceKind
accountScopeId: String
householdScopeId: String?
explicitContextEntityIds: List<String>
source: EntityProvenance
```

At least one of `entityId` or non-blank `rawText` is required. Context IDs must
be explicit typed conversation state, never reconstructed from the last reply
text alone.

### `EntityCandidate`

Contains the candidate entity ID/type/label, matched alias ID when applicable,
signals, and repository-safe display information. It does not expose sensitive
metadata. Candidates are ordered by deterministic signal precedence, then a
stable tiebreaker used only for display; the tiebreaker never resolves equal
candidates.

### `EntityResolution`

```text
status: EntityResolutionStatus
resolvedEntityId: String?
candidates: List<EntityCandidate>
signals: List<EntityMatchSignal>
confidence: EntityResolutionConfidence
reasons: List<String>
risks: List<String>
confirmation: EntityResolutionConfirmation?
```

Only `resolved` may contain `resolvedEntityId`. `ambiguous` and
`needsConfirmation` must retain candidates. Reasons are short business codes,
not AI chain-of-thought.

### Provenance and confirmation

`EntityProvenance` records source type, source record ID, actor, and observed
date. A confirmation request carries stable candidate IDs, expected entity
type, safe display labels, and the consequence of selection. It never targets
an entity by display text alone.

## Invariants

- IDs, scope IDs, and persisted normalized labels are non-blank.
- IDs never change when a canonical label, locale, or alias changes.
- Active aliases are unique per entity by `(normalizedValue, kind)`.
- An alias collision across two active entities is retained as ambiguity.
- An entity cannot merge into itself or into a deleted entity.
- Merge and logical deletion preserve audit history and redirects.
- Sensitive entities and alias additions require explicit user evidence.
- No resolver turns `unknown`, a generic label, or an unscoped pronoun into a
  resolved entity.
- V1 never uses list position or a mutable name as identity.

## Identifier and scope strategy

Reuse `EntityIdGenerator` and UUID v7 for entity IDs. A Firestore random
document ID would also be safe, but using the injected generator keeps the pure
domain testable and consistent with record creation. Deterministic IDs and
label hashes are forbidden because renames, locale changes, and sensitive data
would leak into identity.

V1 stores all entities under an authenticated account scope:

```text
users/{uid}/entities/{entityId}
```

The UID is the authorization boundary and is not embedded in the entity ID.
Household identity is represented by an account-owned household entity and an
optional `householdScopeId`, not by a globally correlatable household key.
Person, place, organization, household, activity, vehicle, pet, and product
entities are account-scoped in V1. Cross-account sharing requires a future
explicit workspace/household membership and ACL design; it must not reuse
guessable or global person identifiers.

## Alias normalization

V1 normalization is deterministic and locale-aware at the boundary:

1. Unicode normalization suitable for stable comparison;
2. trim and collapse whitespace;
3. locale-independent lowercase;
4. normalize apostrophe and dash variants;
5. preserve a display value separately;
6. optionally create a comparison key without diacritics, but never discard the
   original spelling;
7. do not stem plurals, strip titles, translate, or infer nicknames globally.

`Dr Martin` and `docteur Martin` may become candidates for the same person only
when an explicit alias or verified structured source connects them. `mon
médecin` and `le docteur` remain relational/generic references. Titles and
relationship words are parsed into reference signals, not stripped to fabricate
an alias.

## Deterministic resolution V1

Resolution receives an injected reference date and already-scoped candidates.
It performs no I/O; an application service obtains candidates from the
repository first.

Precedence:

1. exact valid entity ID in the same account scope;
2. explicit typed conversation target;
3. explicit verified relation;
4. unique exact active alias plus compatible type and scope;
5. unique exact canonical normalized label plus compatible type and scope;
6. otherwise ambiguity, confirmation, or not found.

An alias match and a canonical-label match on different active entities remain
ambiguous; precedence never hides two plausible identities.

Rules:

- an exact ID in another account is `notFound`, never a cross-account signal;
- incompatible type is `invalid` or `notFound` according to boundary policy;
- two exact aliases yield `ambiguous` even if one was used recently;
- recency may order candidates for presentation but cannot resolve a tie;
- a unique relational expression can be `resolved` only from an explicit,
  verified relation supplied by Profile/Life Context;
- several children for `mon enfant` are `ambiguous`;
- a pronoun is `resolved` only when typed conversation state exposes one
  explicit compatible target; otherwise it is `needsConfirmation` or
  `notFound`;
- fuzzy, phonetic, and probabilistic matching are deferred.

## Explainable confidence

Confidence is an enum derived from auditable signal combinations:

- `exact`: same scoped ID;
- `strong`: one candidate with exact active alias or canonical label,
  compatible type, and no conflicting candidate;
- `insufficient`: all ambiguous, generic, pronoun-only, conflicting, or absent
  evidence.

No arbitrary floating-point score is persisted. If analytics later require a
number, it must be a documented projection from these fixed states and signals,
not an independent decision input.

## Repository contract

The pure engine depends on no repository. Phase 2 provides an abstract
`IdentityRepository` for a future application layer:

```text
findById(scope, entityId)
findByIds(scope, entityIds)
queryCandidates(scope, query)
save(scope, entity)
saveAll(scope, entities)
```

Every operation requires a trimmed, non-empty `IdentityAccountScope`; no global
or implicit account exists. Candidate and ID queries are limited to 20 and
never resolve ambiguity. Results are ordered by entity type, comparison key,
then ID, independently of insertion or database return order. Duplicate input
IDs are rejected. The fake keeps account stores and explicit relation indexes
strictly separate and validates an entire `saveAll` before changing its store.

`IdentityRepositoryQuery` can prefilter exact comparison keys, explicit IDs,
types, statuses, and explicitly indexed relation keys. An optional injected
reference date safely removes inactive temporal aliases; without it the
repository returns a bounded superset and leaves final temporal decisions to
`IdentityEngine`.

`IdentitySerialization` maps entities outside the domain. It writes ISO-8601
UTC dates and all Phase 1 entity/alias fields. Historical reads safely default
missing type to `unknown`, status to `active`, source to `historical`, aliases
and metadata to empty, `updatedAt` to `createdAt`, normalized label to a
deterministic recalculation, and schema version to 1. Unknown additive fields
are ignored but not preserved by a later write. Corrupt required fields,
unknown enum values, invalid dates, malformed aliases, contradictory merges,
and invalid versions fail with typed, non-sensitive errors.

The contract and fake have no Firebase, Flutter, network, disk, UI, service, or
OpenAI dependency. A concrete Firestore repository, transaction policy,
pagination for user-facing lists, rules, and indexes remain future work.

Potential Firestore fields are additive: `entityType`, `canonicalLabel`,
`normalizedLabel`, bounded `aliasKeys`, `status`, `source`, timestamps,
`mergedIntoEntityId`, and `schemaVersion`. Composite indexes may be required for
`entityType + normalizedLabel + status` and `entityType + aliasKeys + status`.
They must be measured and approved separately; this audit creates no index or
collection.

## Compatibility and progressive migration

No global migration is required for V1.

### Read path

- if an optional `...EntityId` exists, resolve by ID and retain the historical
  text as display fallback;
- if absent, keep current text behavior and optionally request bounded
  candidates;
- if resolution is ambiguous, preserve the text and ask for confirmation;
- missing entity documents never erase historical text.

### Additive write path

Examples of future optional fields:

```text
ChildProfile: personEntityId
ActivityModel: activityEntityId, locationEntityId
EventModel: subjectEntityIds, locationEntityId
TaskModel: assigneeEntityId
LifeMemoryFact legacyData/boundary: entityReferences
```

Existing `firstName`, `partnerName`, `childName`, `school`, `doctor`,
`location`, `importantPlaces`, event title, task title, and travel-context text
remain readable. New writes retain both text and ID until adoption and rollback
metrics prove the ID path safe.

### Enrichment and rollback

Entity creation begins only from explicit profile edits or confirmed
conversation flows. Background backfill is deferred. A future idempotent
backfill may propose links but must not silently merge them. Rollback ignores
optional IDs and continues with historical text. Metrics must count resolution
status, candidate count, confirmation rate, unresolved legacy references,
stale IDs, and merge corrections without logging raw labels.

## Integration boundaries

### Profile Engine

Profile supplies explicit verified identity seeds. Identity returns IDs and
resolution results. It never rewrites profile fields without a confirmed
profile command. Profile remains authoritative for explicitly entered facts.

### Memory Engine

Memory may carry optional typed entity references after confirmation. Identity
does not decide whether a fact should be memorized, confirmed, replaced, or
deleted. Deleted/merged entity references are projected safely by the memory
boundary.

### Conversation Engine

Conversation extracts or receives mentions, supplies typed pending context, and
presents clarification. Identity returns structured resolution. Confirmation
must reference candidate IDs and must not collide with event or memory pending
actions.

### Life Context Engine

Life Context composes profile, memory, and resolved identities into a bounded
projection with provenance. It is a consumer and composition boundary, not the
entity source of truth.

### Planning Engine

Planning consumes resolved people and places plus their independently supplied
constraints. It must not implement alias tables or infer that a label is a
specific entity.

### Knowledge Graph

Identity owns node identity, aliases, redirects, and resolution. The future
Knowledge Graph owns typed edges such as household membership, parenthood,
employment, participation, location, ownership, and responsibility. V1 may
consume explicit relation signals supplied by Profile/Life Context, but it does
not author or infer graph relationships.

## Security, privacy, and lifecycle

- Every repository operation requires authenticated account scope.
- Firestore rules must keep entity documents below the owner UID; V1 introduces
  no global lookup collection.
- Household scope never weakens account authorization.
- Sensitive person, child, school, health-contact, home-place, vehicle, and
  temporary aliases receive restricted projections and explicit confirmation.
- Logical deletion preserves minimal audit and makes the entity ineligible for
  ordinary resolution.
- Merge preserves a redirect and audit; it is explicit, reversible only through
  a later controlled workflow, and forbidden across accounts.
- Audit stores actor, timestamp, action, source/target IDs, and business reason,
  not raw conversation or AI reasoning.
- Export includes user-owned entities and active/removed aliases as required by
  product policy. Correction changes labels without changing IDs. Deletion and
  retention periods require a product/legal policy before implementation.
- Alias-level removal supports minimization without deleting the entity.
- Logs and metrics contain status, type, duration, and counts, never canonical
  labels, alias values, medical content, child details, or local file paths.

The current Firestore rules enforce UID ownership. Local SharedPreferences are
device-local but not partitioned by Firebase UID, which is existing security
debt for account switching and must be resolved before treating local entity
cache as multi-account safe.

## Performance and scaling

- Normalize once at command/query boundaries; comparison is linear in the
  bounded candidate count.
- Exact ID lookup is one document read.
- Canonical and alias queries are indexed, scoped, status-filtered, and bounded.
- V1 never scans a user's complete entity set or uses pairwise all-to-all
  comparison.
- Application orchestration batches references and deduplicates IDs to avoid
  N+1 reads.
- A short-lived account-local cache may store non-sensitive identity summaries,
  keyed by UID and invalidated by entity version. No cross-account cache.
- Fuzzy matching and per-request LLM resolution are excluded because they add
  cost, opacity, latency, and false-merge risk.
- Candidate and alias limits must be enforced at both repository and command
  boundaries; proposed defaults are 20 candidates and 50 active aliases per
  entity.

## Observability

Record aggregate metrics for `resolved`, `ambiguous`, `notFound`,
`needsConfirmation`, and `invalid`; signal families used; candidate-count
buckets; repository latency/read count; stale-ID rate; confirmation outcome;
merge correction rate; and legacy-text fallback rate. Structured errors expose
codes only. Dashboards must not contain labels, aliases, UID values, or user
text.

## Test matrix for implementation

### Identifiers

- UUID validity, uniqueness within scope, and injection;
- stable identity after canonical-label rename;
- no collision or visibility across accounts;
- language-invariant ID;
- invalid, blank, self-merge, and cross-scope IDs rejected.

### Aliases and normalization

- exact alias, case, accents, whitespace, apostrophe, and dash variants;
- original display form preserved;
- conflicting aliases remain ambiguous;
- removed and expired aliases excluded;
- temporary alias respects injected reference date;
- relational expressions and pronouns never persist as aliases automatically;
- no automatic nickname, title stripping, plural stemming, or translation.

### Resolution

- exact scoped ID;
- unique canonical label and unique alias;
- no candidate and multiple candidates;
- wrong type and deleted/merged candidate;
- historical text with and without optional ID;
- pronoun without context and with one explicit typed target;
- several people with the same role;
- `mon enfant` with zero, one, and several explicitly related children;
- deterministic output for identical inputs and reference date;
- no mutation for ambiguity.

### Security and privacy

- account and household isolation;
- no global person correlation;
- sensitive entity confirmation;
- merge forbidden across scopes;
- logical deletion and alias-level removal;
- privacy-safe serialization, logs, and metrics;
- generic fixtures only.

### Architecture and persistence

- pure domain imports no Firebase, Flutter, UI, or OpenAI;
- repository replaceable by a fake;
- deeply immutable nested structures;
- bounded repository calls and pagination;
- additive Firestore serialization and unknown-field compatibility;
- legacy profile/event/task/memory reads unchanged;
- indexes represented as an approval-dependent deployment concern;
- batch resolution avoids N+1 calls.

## Exact implementation file plan

Phase 1 creates:

```text
lib/core/identity/entity_types.dart
lib/core/identity/life_entity.dart
lib/core/identity/entity_alias.dart
lib/core/identity/entity_reference.dart
lib/core/identity/entity_candidate.dart
lib/core/identity/entity_resolution.dart
lib/core/identity/entity_normalizer.dart
lib/core/identity/identity_engine.dart
test/core/identity/entity_normalizer_test.dart
test/core/identity/identity_engine_test.dart
test/core/identity/life_entity_test.dart
```

The repository contract, concrete serialization, and application service are
Phase 2 work and are deliberately absent from Phase 1.

It should modify only when required by the phased adoption:

```text
lib/core/identity/entity_identity.dart
lib/models/user_profile.dart
lib/models/life_context/identity_context.dart
lib/models/life_context/life_context_snapshot.dart
lib/services/life_context/user_profile_life_context_mapper.dart
lib/services/conversation_coordinator.dart
lib/models/event_model.dart
lib/models/task_model.dart
lib/models/life_context/memory_context.dart
docs/MASTER_ARCHITECTURE.md
firestore.indexes.json                 approval-dependent, not phase 1
firestore.rules                        only after a separate security review
```

Do not create all adoption fields in phase 1. The list defines likely touch
points across the approved progressive rollout, not one large change.

## Recommended implementation order

1. **Pure domain foundation:** enums, immutable models, normalizer, resolver,
   explainable signals, injected generator/date, and exhaustive unit tests.
2. **Repository contract and fake:** bounded queries, additive serializer,
   idempotent commands, account-scope enforcement tests; review indexes/rules
   without deploying.
3. **Profile seeding:** optional IDs for user, partner, and children with text
   fallback; no background migration.
4. **Conversation clarification:** typed reference input, candidate display,
   pending identity confirmation, collision protection.
5. **Life Context projection:** expose resolved IDs and provenance while keeping
   legacy text.
6. **Domain adoption:** one consumer at a time—event subjects/places, task
   assignee, then memory references—each behind compatibility tests and metrics.

## Product decisions required

- whether and how households can be shared between authenticated accounts;
- which profile edits create entities automatically versus request consent;
- legal retention for deleted entities and audit records;
- merge correction and unmerge policy;
- whether organizations/products ever need a broader-than-account scope;
- localization policy for canonical labels and aliases;
- maximum alias count and user-facing alias management;
- whether a unique verified relationship may resolve a relational expression
  without a confirmation prompt;
- how local data is partitioned or cleared when accounts change.

## V1 limits and future evolution

V1 is exact, scoped, deterministic, and confirmation-first. It excludes fuzzy
similarity, phonetics, embeddings, model-based matching, global directories,
automatic merges, shared-household ACLs, and relation inference. Future
Knowledge Graph work may add typed relationships after entity identity is
stable. Future resolution may add carefully measured signals, but ambiguity and
provenance remain part of the public contract.
