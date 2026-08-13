# ZELIA Master Architecture

## Document status

This document is the constitutional architectural reference for ZELIA. It defines the durable mission, boundaries, principles, ownership model, system relationships, decision framework, and long-term direction of the repository.

ZELIA's approved product mission is to become the personal second brain of its
user. `docs/ZELIA_BRAIN_CONTRACT.md` is the authoritative product contract for
that mission. This architecture must implement it without replacing evidence
with plausible inference or moving deterministic domain truth into generated
language.

It is intentionally not an implementation manual. Individual classes, APIs, schemas, storage layouts, operational commands, and migration procedures belong in narrower documents and in the code itself.

Statements labeled **Current state** describe behavior verified in the repository when this document was created. Statements labeled **Planned architecture** describe an approved direction that is not yet fully implemented. Repository-specific facts must always be rechecked before configuration, security, persistence, or remote work.

This document must evolve deliberately. It should change when ZELIA's mission, system boundaries, architectural ownership, safety model, or long-term direction changes—not whenever a service is renamed or refactored.

### Natural French understanding boundary

**Current state:** V1-NLU.1 introduces a bounded `NaturalLanguageNormalizer`
contract on Flutter and its contract-compatible Node projection. It preserves
the original message, exposes closed normalization codes and ambiguities, and
uses the closed understanding levels `exactMatch`, `normalizedMatch`,
`probableMatch`, `ambiguous`, and `noMatch`. Negation, unresolved references,
multiple actions, and the ambiguous meanings of `plus` cannot authorize a
local action. Node returns a bounded clarification with no action before model
generation for these critical cases.

Flutter local Shopping, Priority and confirmation routing reuse the common
boundary. Date, time and duration parsing expose structured entities and
Planning refuses to apply their values when understanding is ambiguous.
Routine retains its specialized punctuation-aware time normalization because
its recurrence grammar has a distinct verified contract. All consequential
operations still require the existing typed proposal, explicit confirmation,
context revalidation, account scope and idempotent persistence path. The
versioned synthetic French corpus contains 200 non-personal formulations; its
normalization target is 100%, with absolute zero-action invariants for critical
negation and ambiguity. Detailed contracts and V1 limits are documented in
`CONVERSATION_NLU.md` and `INTENTS.md`.

### Conversational event mutation foundation

**Current state:** Phases 4I-A and 4I-B define a closed `event_mutation` backend
action containing `update`, `replace_participant`, or `remove_participant`,
structured target criteria, and only the payload permitted by that operation.
It never carries an event or Identity ID. The server removes malformed or
ungrounded mutations; Flutter validates again and deterministically selects
current events by normalized title, exact date, exact time, and normalized
category.

Zero matches do not create an event. One stable-ID match creates a typed
confirmation. Multiple matches create a bounded, expiring clarification whose
numbered choice is resolved locally without an LLM. Final confirmation reloads
the event and compares it with its immutable snapshot; persistence also checks
the expected `eventRevision` at the document boundary. Firestore mutations use
a transaction, so disappearance, concurrent modification, retry, or a
protected-range conflict cannot silently overwrite a newer event.

Standard updates can change only title, date, time, duration, outbound/return
travel, margin, notes, and category. Participant replacement reuses the typed
explicit participant contract, then the existing Identity resolution,
clarification, confirmed creation, binding, and final revalidation services.
Participant removal is an explicit, separately confirmed link mutation and
never touches the Identity. Both operations reuse the same event selector,
pending system, concurrency snapshot, `EventMutationService`, and persistence
boundary. An event without a participant cannot treat replacement as addition.
Recurrence, event deletion, duplication, participant addition, and bulk updates
remain excluded. Backend context contains no event ID, notes,
account scope, Firestore metadata, participant link, or Identity data. Calendar
growth will require a separate bounded context-window policy; this phase does
not introduce unbounded semantic matching.

Modern events start at `eventRevision` one. Historical documents without the
field read as revision zero and their first modern mutation performs `0 → 1`.
Every later mutation performs exactly `n → n + 1`; Firestore Rules enforce the
same protocol. This global revision is distinct from
`participantIdentityRevision`, which changes only when the participant link is
replaced or removed. Calendar and conversational edits share the same mutation
boundary. SharedPreferences applies the same compare-and-increment contract,
but cannot provide Firestore's multi-process transactional guarantee.

### Offline event synchronization

**Current state:** Phase 4K replaces list-authority synchronization with a
versioned local operation journal. Local `create`, `update`, and `delete`
intentions carry a stable operation ID, event ID, batch ID, expected revision
where required, immutable payload where required, attempt count, and a closed
state. The journal is bounded to 500 retained operations; applied and cancelled
entries are removed, while conflicts and failures remain available for later
product handling. Transient failures are retried at most five times
automatically. Operations captured for an authenticated account retain that
account scope and cannot be replayed under another account. Local activity
created without an authenticated scope remains local and is reported as a
scope conflict rather than being silently attributed at reconnection.

On reconnection, pending operations are replayed deterministically through the
same transactional Firestore document boundaries. Cloud state may rebuild the
local cache only when replay has no conflict or persistence failure. A missing
local event is never treated as cloud deletion. Create retries accept only an
identical existing document, update retries accept only the identical
already-applied next revision, and missing delete retries are idempotent.

Recurring occurrences remain independent event documents at revision one.
Multi-occurrence work shares a stable logical batch ID and uses an explicit
partial-result policy: each child operation has its own durable status, so a
series can never report false global success. This favors resumable offline
work over a server Function; no LLM, Identity repository, or screen owns sync.
SharedPreferences prevents duplicate replay within the active application
service, but does not claim interprocess locking.

Series creation and explicit series deletion use the logical batch identity.
Arbitrary whole-series edits are not enabled: the current materialized
occurrence model cannot yet preserve independent exceptions with a strict
all-or-nothing transaction. Such edits must remain blocked until their target
occurrences and expected revisions can be frozen explicitly.

### Explicit Event conflict resolution

**Current state:** Phase 4L exposes retained synchronization conflicts through
one typed application boundary. A conflict remains attached to its original
operation, account scope and logical batch; it is never removed or replayed
until an explicit closed decision is supplied. Creation conflicts permit cloud
retention, local abandonment, or confirmed recreation with a new ID. Update
conflicts permit cloud retention, local abandonment, or a confirmed rebase
against a freshly read cloud document. Delete conflicts permit cloud retention,
deletion cancellation, or a newly confirmed deletion against the latest
revision. Scope conflicts never permit a write.

The update rebase is deliberately field-delta based and exists only for journal
entries that retain the original base event. Legacy V1 journal entries without
that base cannot be force-rebased. This prevents a complete stale payload from
overwriting unrelated concurrent cloud changes. Decisions that write require a
separate confirmation, Firestore remains authoritative, and resolution receipts
are retained in the same bounded journal to make repeated decisions idempotent.
Batch conflicts remain child conflicts sharing a batch ID; successful children
are never replayed and no aggregate decision hides an occurrence exception.

Conflict rebases that produce a new Event version pass through the same
side-effect-free mutation-invariant boundary as normal conversational Event
updates. The boundary first detects the actual changed fields. Descriptive-only
changes do not invoke planning unnecessarily; date, time, duration, travel,
margin, location context, or recurrence changes are checked against protected
Event intervals and the current profile-derived blocked periods before the
transactional write. A planning conflict is distinct from a revision conflict,
performs no write, and leaves the original journal conflict visible.

The latest cloud revision is still only an input snapshot: the Firestore
transaction verifies it again at write time. If it changed again, resolution
returns a new explicit concurrency result and retains the conflict. Repeated
decisions remain idempotent through the resolving state and bounded resolution
receipt. Legacy journal updates without a base snapshot, participant deltas
that cannot be safely reconstructed, and series-scope changes that cannot
preserve materialized occurrence exceptions fail closed instead of inventing a
merge. The local SharedPreferences recovery guarantee remains process-local;
it is not presented as an interprocess transaction.

## 1. Vision

ZELIA is a French-language AI assistant for the practical organization of personal and family life. It is designed to help a person understand, organize, remember, prioritize, and act on the realities of daily life without requiring the person to become a project manager for their own household.

ZELIA's value comes from dependable assistance across connected domains:

- personal and household context;
- family and children;
- work and availability;
- tasks and priorities;
- shopping;
- appointments and calendar planning;
- travel and safety margins;
- routines and recurring constraints;
- durable memories;
- reminders and notifications.

ZELIA is not merely a conversational interface. Conversation is the primary interaction surface through which the system gathers intent, resolves uncertainty, explains proposals, obtains confirmation, and coordinates deterministic product behavior.

The long-term objective is a trusted life-organization system: contextual enough to be useful, deterministic enough to be dependable, and transparent enough that the user remains in control.

## 2. Product philosophy

### 2.1 Assistance must be dependable

Plausible language is not sufficient evidence that an action is correct or complete. ZELIA must distinguish between:

- understanding a request;
- proposing an action;
- obtaining required information;
- receiving user authorization;
- executing the action;
- confirming actual success.

The system must never claim that data was created, changed, remembered, deleted, scheduled, or sent unless the corresponding operation genuinely succeeded.

### 2.2 The user remains the authority

The user's current explicit instruction takes precedence over inferred preferences, historical context, and generated assumptions. ZELIA may use context to improve a response, but it must not convert context into unrequested action or fabricate consent.

Destructive, irreversible, remote, security-sensitive, or identity-changing operations require clear authority. Confirmation must never be inferred or fabricated.

### 2.3 AI proposes; deterministic systems decide and execute

Generated output is untrusted boundary input. AI may interpret, classify, summarize, or propose. Deterministic application logic must validate generated structures, enforce required information, check conflicts, obtain confirmation, and control persistence.

No language model is the authoritative source for calendar availability, stored memory, identity, security, or operation success.

### 2.4 Context must be useful, bounded, and correctable

Profile and memory context exist to reduce cognitive load. Context must have a known source, a defined lifetime, and a correction or deletion path appropriate to its sensitivity and durability.

Transient requests must not silently become durable identity. Durable facts must not silently become actions. Preferences must not silently become hard constraints.

### 2.5 Graceful capability without forced visible registration

**Current state:** ZELIA remains immediately usable without forcing the user to
create a visible permanent account. Startup reuses the current Firebase session
or creates an anonymous Firebase session before any protected service is used.
Concurrent calls share the same bootstrap. Complete linking to permanent
providers remains a later phase.

Anonymous identity is an authenticated technical state, not unrestricted public access and not a substitute for application attestation, validation, or abuse controls.

## 3. Architectural constitution

The following rules govern every subsystem and future engine.

1. **Inspect reality before changing it.** Current code, callers, models, tests, configuration, and stored-data compatibility must be inspected before implementation.
2. **Never invent architecture.** Similar names do not imply identical responsibilities. Ownership is established through live callers, inputs, outputs, and side effects.
3. **Keep business decisions deterministic.** Generated content crosses a validation boundary before it can affect user data.
4. **Preserve explicit confirmation.** A proposal is not permission to persist an event or perform another consequential operation.
5. **Preserve backward compatibility.** Existing local data, cloud data, legacy fields, and user-visible behavior remain readable unless an approved migration replaces them.
6. **Centralize business rules.** A rule should have one authoritative owner and reusable projections for its consumers.
7. **Avoid silent behavior changes.** Intentional changes require explicit description and regression coverage.
8. **Fail safely.** Missing identity, invalid generated data, persistence failure, conflict, or uncertain context must not produce invented success.
9. **Separate hard constraints from preferences.** Availability constraints block invalid plans; preferences influence ranking but do not become prohibitions without evidence.
10. **Protect complete time ranges.** Planning considers the appointment, outbound travel, return travel, and applicable margin.
11. **Treat tests as executable contracts.** Tests protect behavior, but passing unit tests do not replace live-path and boundary validation.
12. **Prefer incremental correction over broad rewrites.** Refactoring must preserve stable behavior and proceed through reviewable seams.
13. **Keep security layered.** Identity, application attestation, request validation, ownership rules, bounded execution, and safe errors address different threats.
14. **Keep documentation honest.** Current implementation and planned architecture must never be presented as the same thing.

## 4. System context

At the highest level, ZELIA consists of five cooperating areas:

1. **Experience layer** — presents onboarding, profile, chat, calendar, tasks, shopping, and home views.
2. **Application orchestration layer** — manages interaction state, missing information, proposals, confirmations, and coordination between domains.
3. **Deterministic domain layer** — owns planning, memory, priority, profile reasoning, actions, conflicts, recurrence, travel, and persistence rules.
4. **AI interpretation layer** — interprets user language, selects model capacity, produces structured conversational responses, and remains behind strict schemas and client validation.
5. **Identity and data layer** — establishes user ownership and stores local or cloud-backed state under explicit security rules.

The durable conceptual flow is:

```text
User intent
  → conversational interpretation
  → validated structured meaning
  → deterministic domain reasoning
  → missing-information or proposal flow
  → explicit confirmation when required
  → persistence
  → truthful user feedback
```

Implementations may refactor individual services, but this direction of authority must remain.

## 5. Repository architecture

### 5.1 Current state

The repository is a Flutter application with a Node.js Firebase Functions backend.

- The Flutter application owns user experience, local interaction state, deterministic action validation, planning and memory orchestration, and local/cloud persistence facades.
- Firebase Functions owns the remote AI boundary, prompt assembly, intent detection, planning-complexity detection, model routing, strict generated-response structure, and OpenAI integration.
- Firebase Authentication and Firestore are present. Cloud data is organized under user-owned paths and protected by UID-based rules.
- SharedPreferences provides local persistence for profile, task, shopping, and event data.
- Memory and conversation persistence currently depend on authenticated Firestore access.
- Tests are divided between Flutter/Dart behavior and Node backend behavior.
- Historical chat sources are retained under `archive/legacy_sources/` and are not part of the active architecture unless a live caller proves otherwise.

The current Flutter application primarily uses widget-local state, static services, and limited notification signals between screens. The chat screen currently coordinates a large portion of the conversational workflow. This is a verified current-state constraint, not the intended permanent ownership model.

### 5.2 Planned architecture

The long-term architecture should preserve the current product behavior while clarifying boundaries:

- presentation components render state and collect user input;
- application coordinators manage typed workflows and transitions;
- domain engines own reusable deterministic decisions;
- repositories own persistence and synchronization semantics;
- a protected backend gateway owns remote AI invocation;
- schemas and contracts make client/server compatibility explicit;
- identity-scoped data prevents cross-user leakage;
- observability reports failures without exposing private context.

The planned architecture does not mandate a specific state-management framework, folder structure, or class taxonomy. Those are implementation choices and may change while the boundaries above remain stable.

## 6. Source-of-truth ownership

Every important business responsibility must have one explicit authoritative owner. Other layers may project, format, cache, or validate that information, but must not silently redefine it.

| Responsibility | Authoritative source | Permitted consumers and projections |
|---|---|---|
| Product mission and architectural direction | This document and explicit approved product decisions | Roadmaps, design documents, implementation plans |
| Repository operating rules | `AGENTS.md` | Human and AI development workflows |
| Verified current behavior | Live code, callers, tests, and configuration together | Documentation marked as current state |
| User intent in the active interaction | The user's latest explicit instruction | Conversation and domain coordinators |
| Active interaction and action lifecycle state | Typed Conversation Engine (planned; currently `ChatScreen`) | Presentation and domain coordinators |
| User identity and data ownership | Firebase Authentication UID and approved identity lifecycle | Firestore rules, repositories, application state |
| Structured generated response shape | Backend strict response schema | AI integration, contract tests, client validation |
| Acceptance of generated actions | Deterministic client validation and domain rules | Action handling and UI feedback |
| Calendar truth | Persisted event data interpreted by the event/planning domain | Calendar UI, conflict checks, proposals |
| Planning availability | Existing events plus verified hard constraints and complete protected ranges | Proposal generation and scoring |
| Planning preferences | Explicit structured profile or memory preferences | Planning windows and ranking |
| Event creation authorization | Explicit user confirmation in the active workflow | Event persistence and notification |
| Durable memory truth | Successfully persisted, user-owned memory records | Context building and reasoning |
| Profile truth | Successfully persisted user profile, with current explicit user updates taking precedence | Context and planning projections |
| Task and shopping truth | Their persisted domain records | Home, task, shopping, priority, and conversation views |
| Security access policy | Approved identity model, backend enforcement, and checked-in rules/configuration | Clients, Functions, repositories |

When two implementations appear to own the same rule, future work must trace their callers and effects, designate authority, and either preserve a deliberate defense-in-depth boundary or remove actual duplication safely.

## 7. Engine model

An engine is a cohesive domain capability with explicit inputs, outputs, invariants, and consumers. A class or filename containing “engine” is not sufficient evidence that an architectural engine exists.

### 7.1 Conversation Engine

**C.1 implemented boundary.** `ConversationSessionController` is the canonical
application orchestrator. It owns the immutable visible session state, message
ordering, request generation, double-send protection, logical cancellation,
bounded backend retry, safe errors and one-shot UI effects.

`ConversationCoordinator` remains the typed business coordinator. It owns the
validated response pipeline, response guards, Event mutations, Identity and
Memory confirmations and their domain continuations. The session controller
does not replace or duplicate these rules.

`SmartPlanningContinuationCoordinator` closes the historical multi-step
Planning gap. It owns one immutable, schema-1 continuation bound to the session
generation. Closed types represent planning consent, duration, outbound and
return travel, slot choice, confirmation and bounded alternative search.
Typed fields replace every former pending `Map` from `ChatScreen`: Task,
grouped Tasks, proposal options, selected option, proposal, margin and travel
durations. The coordinator delegates availability, protected periods,
revalidation, conflicts and Event persistence to the existing Planning/Event
services; it is not a second Planning Engine.

`ChatScreen` is now a passive Flutter presentation. It owns only text, focus
and scroll presentation, renders immutable state, consumes effects and
dispatches closed UI intentions. It does not construct a backend request, load
domains, parse responses or call a mutation service.

**V.1 voice input boundary.** `VoiceRecognitionCoordinator` is the sole
Speech-to-Text application coordinator. The injected
`SpeechRecognitionPlatformGateway` isolates `speech_to_text`,
`permission_handler`, native status and native errors. Closed availability,
permission, failure, interruption and session states bind every callback to a
voice-session ID and the current conversation generation. Partial results stay
ephemeral. During recognition, the text composer becomes a compact recording
capsule whose visualization is driven by the plugin's native sound-level
callback. Cancel discards only the active dictation. Validate stops recognition,
briefly allows the last native result to arrive, then inserts the best available
transcript at the reliable composer cursor (or appends it) without sending it.
The ordinary Send control remains the only path from that editable text to
`ConversationSessionController`.

Permission reading is silent. A native prompt follows only the microphone
gesture and a separate explanation/authorization action. Silence, maximum
duration, result size, fragments, initialization and stopping are bounded.
Inactive/background/detached states cancel or dispose recognition, invalidate
late callbacks and never resume automatically. Account or conversation
changes invalidate the active voice session. No audio file, audio cache,
backend audio transport, transcript diagnostic, TTS, realtime, hotword or
background listening exists in V.1.

**Planned architecture:** The Conversation Engine owns workflow state and transitions. It does not own domain truth, persistence rules, planning conflict rules, security enforcement, or Life Context facts. It coordinates authoritative domain engines and repositories through typed contracts.

### 7.2 Life Context Engine

**LC.1 implemented foundation.** `LifeContextEngine.buildCanonicalSnapshot`
is the single multi-domain construction boundary. Six injected, read-only
adapters project HumanModel, confirmed Identity links, Event, Task, the
currently structured legacy Routine source, and the consent-filterable Memory
source. Each domain keeps ownership and persistence of its own records; Life
Context is reconstructible and is never a second database.

The canonical snapshot schema is version 5 and each new domain section starts
at section schema version 1. It contains an authenticated internal
account scope, a random non-personal snapshot ID, generation time, global
complete/partial/unavailable state, typed domain sections, and source metadata.
Metadata distinguishes available, stale, empty, unavailable, unsupported,
corrupt, and account-mismatched data, with read time, optional revision,
sync state, locality, and bounded item count. Independent adapters load in
parallel with a bounded timeout; a non-essential domain failure produces an
explicit partial snapshot rather than a false empty list.

HumanModel remains the human source of truth and its retained legacy payload is
never serialized into the canonical snapshot. Identity projection contains
only stable links already attached to HumanPerson records; no repository-wide
identity export or mutation occurs. Event and Task use account-bound read-only
service methods. Their historical unscoped local caches are deliberately not
used by LC.1 because that could mix accounts. Routine currently adapts only
explicit `personalActivities` and school time ranges retained in the
account-scoped HumanModel legacy payload; arbitrary memories are not routines.

The older synchronous profile/memory projection remains solely as a
compatibility input to current conversation and planning consumers. LC.1 does
not send the canonical multi-domain snapshot to OpenAI. LC.2 calculates
cross-domain relationships and technical consequences, while LC.3 owns the
bounded, filtered projections described below.

**LC.1 production boundary.** `LifeContextProduction` is the single
account-scoped coordinator over LC.1, LC.2 and LC.3. It retains one immutable,
reconstructible snapshot and relation graph for the active account, serializes
concurrent refreshes, rejects results from an obsolete account generation and
exposes one projection generation to every migrated consumer. It is a cache
and coordination boundary, never a persistence owner.

Freshness thresholds and source budgets are centralized by domain. A fresh
snapshot is reused across consumers; Task and Event changes invalidate only
their sections, while a Human invalidation also invalidates the derived
Identity and Routine sections. Account change invalidates everything
immediately. Source truncation, stale, unavailable, unsupported, corrupt and
account-mismatched states remain explicit and prevent a false `complete`
snapshot.

Conversation, Priority consultation, proactive Priority, N.2 detection, the
production Smart Planning continuation gateway and general Memory reasoning
consume this shared production generation. Capability compatibility is
evaluated separately from global health: an unavailable Memory section does
not block a Task-only priority or a Planning request that does not depend on a
memory, while Planning remains blocked without sufficiently current Event and
Routine sections.

**LC.2 consumer migration.** Smart Planning obtains one bounded Planning
projection and freezes its generation with the proposal. The adapter preserves
protected Event periods, separate outbound and return travel, margins,
recurrence and revision, plus confirmed Routine periods. The Task continuation
also requires the Task section. A later generation does not silently rewrite a
presented proposal: the selected slot is revalidated against current Event and
Routine constraints before final confirmation.

Memory reasoning obtains a typed context only from the canonical Memory
section. Confirmed, active, non-expired memories are eligible; proposed,
rejected, superseded, ambiguous and explicit-health records remain excluded.
Only an explicitly typed recurring Routine memory may enter the narrow Planning
compatibility bridge. Historical readers remain callable only for unmigrated
compatibility tests and callers; they are not used by the production Smart
Planning gateway.

**LC.2 relation layer.** `LifeContextRelationEngine.build` is the only
canonical relation-graph builder. Its sole input is one validated LC.1
`LifeContextSnapshot`; it has no repository, persistence, UI, model-provider,
or domain-write dependency. The resulting immutable schema-v1
`LifeContextGraph` is reconstructible and is never a business source of truth.

Graph nodes use deterministic technical IDs built from domain, resource type,
and stable source ID. They deliberately omit visible labels, free text,
addresses, medical data, and source payloads. Directed relations retain their
source record, section, read time, freshness, confirmation, temporal range,
snapshot, evidence type, and registered rule/version. LC.1 now preserves
ordered Human relationship/responsibility references and explicit residence
associations so LC.2 never has to infer direction from a sorted list.

The closed rule registry currently projects only:

- explicit Human relationships;
- explicit person-to-household memberships;
- explicit household/person-to-residence associations;
- explicit responsible-person-to-subject responsibilities;
- persisted HumanPerson-to-Identity links;
- structured Identity-to-Event participants;
- structured HumanPerson-to-Routine associations;
- explicit recurring-series membership.

Task has no structured cross-domain link today, so LC.2 creates no Task
relation or dependency. A free participant name, matching title, nearby time,
family relationship, double household membership, or responsibility never
creates a dependency. Routine data without a stable HumanPerson reference also
remains unlinked.

`LifeContextGraphQuery` provides deterministic incoming/outgoing/type/time
queries, household, residence, responsibility and Event-participant lookups,
provenance explanations, bounded dependency traversal, deterministic cycle
detection, and bounded technical consequence paths. A relation only states
association. A dependency is the separate directed
prerequisite-to-dependent contract and requires a registered explicit rule. A
technical consequence only identifies projections that must be revalidated;
it never recommends, prioritizes, moves, or writes anything.

Historical, future, rejected, proposed, inferred, and needs-confirmation
records remain distinguishable. Rejected records are never active. All graph
construction and traversals validate scope, references, duplicates, periods,
versions, rule registration, depth, and visit bounds.

**LC.3 consumer projections.** `LifeContextProjectionEngine.build` is the
single projection boundary. It accepts only one validated LC.1 snapshot, its
optional matching LC.2 graph, and a closed versioned consumer contract. It
never reads a repository, persists a projection, calls a model provider, or
writes a domain. Conversation and Planning use different contracts rather
than receiving a universal life payload.

Each contract fixes its purpose, allowed sections and sensitivity levels,
global and per-section budgets, temporal window, freshness policy,
confirmation policy, relation depth/count, item count, and truncation policy.
Unknown purposes, invalid or absent budgets, future schema versions, and
unclassified facts fail closed. Budget cost is the deterministic count of one
unit per item plus one per typed fact. Selection is stable: confirmation,
freshness, and technical identifier are used without urgency, importance,
emotion, text analysis, or recommendation. An item is included whole or
omitted; global and section omission counts and truncation warnings remain
explicit.

The closed sensitivity taxonomy is technical, ordinary personal, private
personal, sensitive, and highly sensitive. Unclassified fields are excluded.
Highly sensitive data is forbidden in this phase. Medical notes, allergies,
blood group, doctor and emergency-contact data, authentication material,
secrets, full addresses, arbitrary JSON, the retained legacy payload, raw
Firestore documents, complete source models, snapshot, and graph are never
projected. Free Event, Task, or Routine text is available only to the
Conversation contract, normalized and hard-bounded; Planning receives
temporal facts, travel, margins, recurrence, sync/conflict state, revisions,
and explicit temporal responsibilities without names or notes.

Every projected section preserves fresh, stale, empty, unavailable, corrupt,
or unsupported state. Required missing domains fail explicitly; allowed stale
or partial inputs remain marked rather than becoming false empty lists.
Rejected facts are always excluded, uncertain facts require contract
permission, inferred facts retain provenance, and history is opt-in.
Relations are bounded and never expand the complete LC.2 graph.

Compatibility adapters translate the Conversation projection into the
existing `ChatBackendRequest` shape and the Planning projection into typed
temporal facts. They never serialize LC.1, LC.2, or `UserProfile` wholesale.
The current production Conversation, Priority, Smart Planning and Memory
Reasoning workflows use the shared LC.1 production snapshot and their distinct
LC.3 contracts. LC.3 adds no second multi-domain reader and does not silently
send an additional context to OpenAI. Projection and ranking remain separate:
Life Context never calculates a Priority score or a Planning decision.

### 7.3 Profile Engine

**Current state (V1-PR.1):** Profile models, persistence, structured context
building, and planning reasoning exist, but responsibilities remain distributed
between application state, a large profile screen, and services. A first pure,
versioned correction boundary now accepts only the closed set of Profile-owned
fields, validates bounded typed values, preserves every Human-owned identity
and family field, and carries an explicit expected revision. It does not read,
persist, infer, reconcile Human entities or alter Life Context. The existing
screen and revisioned persistence remain unchanged pending controlled
integration. PR.2 now compares an existing revisioned Profile with the proposed
value, sends only changed Profile-owned fields through PR.1, and uses the
validated result for the existing revisioned mutation. Human-owned-only
changes do not create a Profile mutation, while initial compatibility creation
and the established local, journal, ledger and cloud paths remain unchanged.

**Planned architecture:** The Profile Engine owns stable user-provided context, validation, correction, and domain projections. It does not own inferred conversational memory.

### 7.4 Memory Engine

**M.1 policy foundation.** `MemoryPolicy` schema v1 is account-scoped and
defaults restrictively to `askEveryTime`, with health disabled. General modes
are automatic, confirmation for every item, and pause. Health has its own
disabled, confirmation-per-item, and explicitly enabled policy; general
automatic mode never grants health consent. `MemoryPolicyEngine` is the closed,
pure decision boundary. It rejects pauses, duplicates, structured-domain
ownership, contradictions, highly sensitive content, and missing health
consent before persistence. It never reads a repository, calls a model, or
decides whether free text is true.

Policy transitions are additive: they neither delete existing memories nor
approve pending proposals, alter routines, or ingest paused conversations
retroactively. A pause blocks new proposals and writes while existing memories
remain readable under the consumer contract. Settings are stored locally under
an account-scoped, versioned key; cross-device policy synchronization is
deliberately deferred to M.2.

`MemoryContext` schema v1 is the typed compatibility projection over the
existing `users/{uid}/memories` source. It preserves lifecycle, confirmation,
provenance, sensitivity, temporal bounds, explicit health classification, and
optional structured-domain references without rewriting or deleting legacy
documents. Ambiguous legacy records remain unconfirmed. Memory is now a typed
LC.1 domain section with availability, freshness, policy state, and a bounded
item count.

LC.3 Conversation selects only active, policy-authorized, non-duplicated
memory items under its Memory section budget. Explicit health memories are
excluded in M.1's current Conversation contract. The single
`MemoryProjectionBackendSerializer` emits only bounded legacy-compatible
`memories` maps from either the LC.3 section or the already-filtered historical
selection; it never receives a repository, snapshot, graph, profile, or full
`MemoryContext`. Planning excludes the Memory domain. A narrowly scoped
compatibility bridge preserves only historical records explicitly categorized
as recurring routines until Routine owns their migration; free preferences,
facts, and constraints never become planning rules.

The profile exposes only the minimal policy settings. The complete memory
library, correction/deletion UI, versioned offline synchronization and
multi-device conflicts remain M.2/M.3 work.

### 7.5 Routine Engine

**Current state (V1-RO.1):** Profile schedules and recurring memories can
produce blocked planning periods. Weekly, weekday, biweekly, and monthly
nth/last-weekday matching capabilities exist. A first typed Routine boundary
now projects active canonical routines onto a bounded civil-date window. Its
occurrences contain stable technical identity, local-clock timing, travel,
margin and source revision time, but no invented timezone and no user-facing
title. Cancelled routines are excluded, account mismatch fails closed, and the
projection never creates Events, persists, schedules or notifies. Existing
Planning recurrence behavior remains unchanged until a controlled migration.
RO.2 adds the account-scoped application service that loads canonical routines
from the production repository and delegates the bounded dated calculation to
RO.1. The service fails before loading for an empty account and still creates
no persisted occurrence or Event. RO.3 makes recurrence-date applicability a
single pure rule shared by the canonical Routine projection and the existing
Planning compatibility adapter. The adapter alone preserves historical
blocked periods with no configured day; canonical routines remain strict.
RO.4 can resolve that bounded local-clock projection to explicit UTC instants
only when a valid IANA timezone is supplied. It exposes the complete protected
range (outbound travel, duration, return travel and margin), rejects impossible
local wall times, contains no user-facing content, and still neither creates an
Event nor schedules a notification.
RO.5 can compare those protected Routine occurrences with canonical Event
protected ranges over a bounded horizon. It emits only confirmed structured
conflict evidence for N.2; it does not itself notify, persist, resolve, or
modify either domain. RO.6 connects this proof to the event-driven N.2 input
provider over its fourteen-day horizon. Event and Routine conflict sources
fail independently, so one unavailable source cannot erase valid evidence
from the other; no polling or background worker is added.

The Agenda projection also reunites canonical Routine records with structured
Profile schedules (personal activities, work ranges, school ranges and
activities belonging to another household person). These items remain
read-only lightweight schedule rows and are never persisted as Events. Their
kind and subject remain explicit: primary-person routines, activities and work
can protect time, while another person's school or activity is visible context
and does not become a primary-user conflict without a separate typed
consequence. The same deterministic catalog is used by conversation and
Agenda, so a confirmed dated cancellation hides only that profile-sourced
occurrence and leaves the following recurrence visible.

**Planned architecture:** The Routine Engine provides one authoritative recurrence vocabulary and dated projection of routines for planning, notifications, and future organization features. A routine remains distinct from a generated series of persisted calendar events unless explicitly converted.

### 7.6 Planning Engine

**Current state:** Planning is the most mature engine family. It includes drafts, missing-information collection, proposal generation, windows, scoring, profile and memory constraints, school schedules, recurrence matching, travel, margins, protected ranges, conflict detection, selected-slot revalidation, explicit confirmation, event persistence, and legacy compatibility.

The durable planning lifecycle is:

```text
collect required facts
  → build a planning request
  → apply hard constraints and preferences
  → generate and score feasible proposals
  → let the user select
  → reconstruct and revalidate the selected slot
  → request explicit confirmation
  → persist
```

**Planned architecture:** Planning retains its deterministic core while conversational state moves behind a typed coordinator. All future planning features must preserve complete protected ranges and must not turn preferences into fabricated constraints.

### 7.7 Priority Engine

**Current state (V1-R.1):** `PriorityEngine` is the canonical deterministic
scoring boundary. It consumes `PriorityCandidate` values built only from a
validated LC.3 projection. A separate bounded input may carry confirmed LC.2
technical consequences at depth exactly one. It does not read repositories,
persist scores, call OpenAI, write a domain, recommend an action, or alter
planning.

Formula version 2 normalizes every positive dimension to `[0, 1]` and produces
a score bounded to `[0, 100]`. Its centralized weights are urgency 25%,
explicit importance 25%, deadline pressure 25%, effort 5%, explicit
flexibility 10%, and confirmed direct impact 10%. Data quality applies a
separate uncertainty penalty of at most 10%. Effort is neutral on its own and
only changes deadline pressure when both duration and remaining time are
structured; short work is therefore not automatically favored.

Le composant d’impact accepte aussi une conséquence métier fermée et déjà
structurée (`healthSafety`, `legalAdministrative`, `financial`,
`otherPersonCommitment`, `work`, `essentialLogistics` ou
`comfortPreference`) avec un niveau fermé. Aucun mot du titre ou des notes ne
peut créer cette conséquence. Une conséquence inconnue reste une information
manquante et neutre.

Missing deadline, effort, importance, flexibility, impact, or freshness stays
explicit. Neutral values permit partial scoring but never become fabricated
facts. Deadline thresholds are versioned and evaluated in UTC. Scores preserve
component provenance, confidence, missing-data codes, and technical reason
codes; user-facing explanations remain R.3.

Ranking is bounded and deterministic: final score descending, nearest
deadline/start, rigidity, structured consequence, creation date, source
confirmation, freshness, source ID, stable technical ID, then an explicit
formula-V2 technical domain table. The domain table is independent from enum
ordinals and expresses no business importance. Ranking never uses a visible
label, Firestore order, family situation, gender, marital status, children,
work/personal category, medical data, or text keywords.

The adapter creates active Task candidates and fixed Event commitments from
LC.3. A future or currently running Event requires a coherent structured end;
an Event whose end is reached is excluded, and a running Event does not receive
an overdue reason merely because its start has passed. It creates a Routine
occurrence only when an explicit structured `actionRequired` marker and a dated
occurrence exist. It can consume a confirmed projection explicitly typed
`constraint` only when its status is exactly active and its half-open validity
window contains the injected calculation date. Proposed, rejected, superseded,
expired, unknown-status, free Memory and Human facts never become candidates.
The adapter does not calculate Routine occurrences or reinterpret Memory text.

**Legacy transition debt:** `AiPriorityService`,
`PriorityEngineService`, `TimePriorityService`, and
`SmartPlanningService.priorityScore` still drive existing Home, Tasks, and
smart-planning behavior. They contain text/category keyword rules and
historical fixed bonuses. R.1 deliberately does not switch visible ordering;
their removal and product activation require a controlled migration to the
LC.3 adapter. They are not canonical R.1 inputs or implementations.

**Next boundaries:** R.2 may propagate explicit dependency chains with its own
bounds. R.3 may translate existing score components into short user-facing
explanations. Neither concern belongs to formula version 1.

#### V1-R.2 — Propagation des dépendances explicites

`PriorityPropagationEngine` ajoute une projection reconstructible au-dessus du
classement direct R.1 et du graphe LC.2. Il ne construit aucun graphe et ne lit
aucun domaine : son entrée est exclusivement `PriorityRanking` plus
`LifeContextGraph`. Le compte et le snapshot doivent correspondre.

Une relation LC.2 ne propage jamais une priorité. Seules les arêtes
`LifeContextDependency`, orientées `prérequis → dépendant`, sont considérées.
L’influence circule dans le sens contrôlé `dépendant → prérequis` : le score
direct d’un élément dépendant peut renforcer le prérequis qui le bloque ou
qu’il requiert. Le dépendant ne reçoit pas automatiquement le score du
prérequis et aucune arête inverse n’est inventée.

Le registre R.2 version 1 est fermé :

| Type LC.2 | Propagation | Coefficient |
|---|---:|---:|
| `requires` | oui | 0,20 |
| `blocks` | oui | 0,25 |
| `follows` | oui, profondeur 2 maximum | 0,10 |
| `explicitUserDependency` | oui | 0,20 |
| `belongsTo` | non | 0 |
| `scheduledBy` | non | 0 |
| `generatedFrom` | non | 0 |
| `custom` | non supporté | 0 |

La formule est
`scoreDirectSource × coefficientType × facteurProfondeur × facteurConfirmation × facteurFraîcheur`.
Les facteurs de profondeur sont 1,00, 0,50 et 0,25 aux profondeurs 1, 2 et 3.
Une influence est plafonnée à 12 points, les cinq principales influences d’un
candidat sont retenues, et leur somme est plafonnée à 25 points. Le score
ajusté reste dans `[0, 100]`; le score direct R.1 reste conservé séparément.

Par défaut, une dépendance confirmée utilise un facteur 1. Une dépendance
inférée n’est utilisable que si sa règle LC.2 est enregistrée et reçoit un
facteur 0,50. Les états proposé, à confirmer, rejeté et historique ne
propagent pas. Une source périmée reçoit un facteur 0,50 et une fraîcheur
inconnue un facteur 0,25 avec état `unavailable`; une structure corrompue est
refusée par les validateurs LC.2/R.2.

Les parcours sont limités à trois niveaux, 100 nœuds et 200 arêtes. Les arêtes
et chemins sont dédupliqués. Les cycles de dépendances sont repris de
`LifeContextGraphQuery`, signalés, puis coupés lorsque le parcours rencontrerait
un nœud déjà présent dans le chemin. Une relation cyclique ordinaire n’est pas
un cycle de priorité. Un impact direct R.1 portant déjà la même règle et le
même prérequis n’est pas recompensé par R.2.

Le classement ajusté utilise successivement score ajusté, score direct,
échéance, rigidité, confirmation, fraîcheur et identifiant technique. Il reste
borné et indépendant de l’ordre d’entrée. Aucun titre, nom, foyer, genre,
relation familiale, catégorie professionnelle, mémoire libre ou donnée de
santé n’entre dans l’association ou la formule.

R.2 n’est pas activé dans les listes visibles. Les moteurs historiques restent
la dette de migration déjà décrite par R.1. R.3 pourra transformer les chemins,
composants et codes techniques en explications utilisateur ; R.2 ne produit
aucune recommandation ni phrase finale.

#### V1-R.3 — Explications déterministes des priorités

`PriorityExplanationEngine` transforme exclusivement les composants R.1 et les
résultats propagés R.2 en explications françaises bornées. Il ne reçoit ni
titre, ni description, ni libellé humain et ne consulte aucun repository. Le
registre versionné `PriorityExplanationRegistry` est fermé : toute formulation
correspond à un code calculé connu, et un code inconnu invalide l’explication.
Il n’existe donc aucune justification libre ou reconstruite après le calcul.

La forme courte retient au plus deux facteurs dominants parmi trois raisons
principales, selon la contribution numérique absolue puis un ordre fermé. La
forme détaillée sépare score direct, facteurs positifs, facteurs neutres ou
réducteurs, données manquantes, dépendances explicites et limites du calcul.
Les paragraphes, le texte total, les raisons secondaires et le nombre
d’explications de classement sont plafonnés.

Une importance absente reste décrite comme inconnue et neutre. Une échéance
absente n’est jamais dite lointaine. L’effort n’est expliqué par rapport au
temps restant que lorsque R.1 l’a effectivement comparé. La flexibilité et
l’impact direct proviennent uniquement de leurs champs structurés. La
fraîcheur limitée, un calcul partiel et les données manquantes restent visibles
sans culpabilisation.

La propagation est présentée séparément du score direct uniquement lorsque sa
contribution est non nulle. Les cycles, influences incertaines, profondeurs et
troncatures sont signalés sans exposer chemins, identifiants de dépendances ou
coefficients internes. Une absence de propagation est elle aussi explicite.

Les comparaisons suivent exactement les départages canoniques R.2 : score
ajusté, score direct, échéance, rigidité, confirmation, fraîcheur, puis ordre
stable. Le dernier départage n’expose aucun identifiant et ne prétend pas qu’un
élément est objectivement plus important. À structure identique, situation
familiale, genre, domaine visible, nom ou catégorie ne peuvent modifier le
texte.

`PriorityExplanationPanel` est un composant de présentation testable qui reçoit
une explication déjà calculée. Il ne charge aucune donnée et ne calcule aucune
raison. Le classement canonique n’étant pas encore activé dans les écrans
produit, ce composant n’est pas branché sur les scores legacy et aucun ordre
visible n’est modifié. Une future frontière C.1 pourra consommer une
représentation courte et bornée, mais R.3 ne modifie ni payload conversationnel
ni prompt.

#### V1-R.4 — Suggestions informatives de priorité

`PrioritySuggestionBuilder` est une projection pure et bornée de
`PriorityRanking`. Il ne reclasse pas les candidats, ne lit aucun repository,
ne persiste rien et ne crée ni action, ni notification, ni proposition de
planning. Une passe utilise une seule date injectée, refuse un classement futur
ou âgé de quinze minutes, et produit au plus trois suggestions.
Les candidats sont parcourus strictement dans l’ordre déjà fourni par
`PriorityRanking`; le type, la sévérité et l’horizon d’une suggestion ne
constituent jamais un second classement. Un candidat sans suggestion est
simplement ignoré, puis la lecture continue jusqu’à trois résultats.

Les types fermés actuellement retenus sont `actSoon`, `prepare`,
`clarifyMissingInformation`, `reviewConflict`, `protectFixedCommitment`,
`reviewOverdueItem` et `monitorDeadline`. Une suggestion est émise seulement
si une intervention informative est prouvée : proximité temporelle, retard
avec conséquence structurée, engagement fixe futur, information manquante qui
bloque réellement l’évaluation, ou conflit déjà confirmé par N.2. Les candidats
ordinaires, lointains ou en cours ne deviennent pas artificiellement urgents.

Les horizons sont `now`, `nextTwoHours`, `today`, `nextTwentyFourHours`,
`nextThreeDays` et `later`. La préparation avec trajet exige un trajet aller
structuré; le trajet retour n’est jamais substitué et une marge absente reste
absente. R.4 ne calcule aucun chevauchement : `reviewConflict` consomme
exclusivement un signal N.2 actuel fondé sur la frontière de conflit canonique.
Tous les participants techniques du signal doivent être présents dans le
ranking. Les preuves équivalentes sont canonicalisées par participants,
révisions et intervalles; une preuve partielle ou plusieurs preuves
incompatibles concernant le même participant échouent fermées. R.4 informe et
propose une revue; il ne choisit aucun gagnant et toute future modification
reste soumise aux confirmations A.1–A.3.

L’identité d’une suggestion est une empreinte déterministe du scope, du type,
des identifiants techniques triés, des versions et de l’horizon. Elle ne
contient aucun texte, titre, nom, lieu, relation ou donnée médicale. Une seule
suggestion principale est conservée par candidat et les preuves équivalentes
de conflit sont regroupées. Il n’existe volontairement ni persistance,
cooldown, registre ni connexion au scheduler dans R.4.

`PrioritySuggestionConversationContextBuilder` fournit une projection locale,
en lecture seule, avec des formulations françaises fermées. Elle n’est pas
ajoutée au schéma Functions et ne permet donc pas au modèle de recalculer
l’ordre ou d’inventer une suggestion. Le branchement produit à une réponse
locale du chat reste une étape d’intégration ultérieure : cette phase n’ajoute
ni nouveau payload backend, ni écran, ni interception du chat classique.

**Current state (V1-R.5):** une consultation explicite des priorités est
détectée par un vocabulaire fermé dans `ConversationCoordinator`, après les
continuations conversationnelles actives et avant la construction d'une
requête backend. La route locale recharge la projection Life Context canonique,
utilise une `referenceDate` unique, puis appelle dans l'ordre
`PriorityCandidateAdapter`, `PriorityEngine`, `PrioritySuggestionBuilder` et
`PrioritySuggestionConversationContextBuilder`. La réponse, limitée à trois
éléments et conservant l'ordre du ranking, est insérée par
`ConversationSessionController` comme tout message assistant. Aucun modèle,
payload d'action, mémoire, notification ou état persistant de suggestion
n'intervient dans ce parcours.

**Current state (V1-R.6 / Priority 2C):** la proactivité de priorité reste une
projection locale, déterministe et sans effet de bord. Après chargement complet
du Life Context canonique, le Dashboard des tâches réutilise strictement
`PriorityCandidateAdapter`, `PriorityEngine` et `PrioritySuggestionBuilder`,
puis soumet leur ordre inchangé à `ProactiveSuggestionPolicy`. La décision
fermée est soit `noSuggestion`, soit `showSuggestion`, avec au maximum une
suggestion visible dans la carte `Suggestion Zelia` existante.

La politique échoue fermée lorsque le contexte est partiel, qu'une interaction
conversationnelle ou Smart Planning attend une réponse, qu'aucune action V1
n'est disponible, que les preuves sont insuffisantes, ou que la même situation
matérielle a déjà été présentée. Les identités et empreintes sont dérivées des
types, références techniques, raisons, horizon et révisions, jamais du texte
d'affichage. Un registre local account-scoped, borné et sauvegardé conserve les
présentations, rejets, actions et accomplissements; une journée civile locale
borne la répétition. Le quota de session n'est consommé qu'après confirmation
du rendu et écriture du reçu `shown`; une décision `noSuggestion` ou une simple
réservation de présentation ne le consomme jamais. Une suggestion `dismissed`
ou `completed` ne réapparaît pas sans changement matériel.

La fermeture est explicite et un CTA ouvre uniquement le parcours Task ou
Agenda existant. Aucune tâche, aucun événement, aucune mémoire et aucune
confirmation ne sont créés implicitement. Cette phase n'appelle ni OpenAI ni
Firebase Functions, n'injecte aucun message dans le chat et ne programme aucune
notification push.

### 7.8 Reasoning Engine

**Current state (V1-RE.1 / V1-RE.2 / V1-RE.3 / V1-RE.4):** Reasoning remains distributed across profile
reasoning, memory reasoning, planning services, prompt context, and model
selection. A first pure construction boundary now produces a versioned,
account-scoped and read-only `ReasoningInput` from typed Conversation workflow
state and a bounded Conversation-purpose Life Context projection. It exposes
only content-free workflow metadata, marks partial context explicitly and
fails closed on account, purpose, version and time mismatches. It does not call
a model, persist, confirm, schedule, resolve conflicts or execute a domain
action. There is still no general-purpose reasoning executor.

RE.2 derives only deterministic structural observations: multi-domain evidence
coverage, an active typed workflow, limited context, and unavailable context
sections. Observations contain closed reason codes and bounded technical
references, never fact values or display text. They are not recommendations,
scores, explanations for the user, actions, or authorization.

RE.3 reduces those observations to one deterministic assessment with a closed
outcome and the exact bounded observation identifiers that justify it. Limited
context takes precedence, followed by an active typed workflow, complete
multi-domain evidence, then explicit insufficient evidence. The assessment is
not user-facing copy, a recommendation, a score, an action, or authorization.

RE.4 provides one pure composition boundary that builds RE.1, derives RE.2 and
assesses RE.3 in sequence. Its versioned result verifies that input,
observations and assessment share one account, identity, timestamp and purpose.
It still does not call a model, generate presentation copy, persist, authorize,
confirm or execute anything.

RE.5 adds the account-scoped application boundary that loads the bounded
Conversation-purpose Life Context projection from the production owner and
passes it, with content-free Conversation workflow state, through RE.1-4. Empty
or mismatched accounts fail closed. The result remains internal read-only
assessment data and still cannot produce copy, recommend, authorize or act.
Daily-life regression scenarios now protect the first composed uses: Task plus
Event plus Routine can make context structurally ready; an active confirmation
still takes precedence; truncated or unavailable context forces a limited
assessment; and one isolated domain remains insufficient. Scenario evidence
also remains content-free.
The proactive Priority production factory now obtains that assessment through
RE.5 and passes it only to a read-only presentation gate. An active workflow
always blocks presentation. Limited context blocks only a suggestion that
depends on supporting cross-domain candidates; it cannot hide a safe,
single-domain Task suggestion merely because an unrelated optional section is
limited. The existing deterministic Priority policy remains in charge, and
Reasoning cannot create, rank, rewrite or execute a suggestion.

**Planned architecture:** The Reasoning Engine consumes typed conversation state and typed Life Context projections to support multi-domain organization. It must not replace deterministic domain engines or the domain owners of conflict, persistence, confirmation, or security.

### 7.9 Task Engine

**Current state (V1-T.1):** Tasks have a model, local/cloud persistence,
conversational creation, priority processing, and dedicated UI. A first pure,
versioned lifecycle boundary now validates the closed transitions create,
update, complete, reopen and delete. It requires stable identity and explicit
expected revision, forbids hiding completion inside a generic update, and
produces only a non-executable transition description. It does not load,
persist, authorize, confirm, schedule, prioritize or notify. Production Task
persistence still follows the existing revisioned services until a separately
validated integration phase. T.2 now routes the production reconciliation
decision through T.1 before creating the existing revisioned mutation. Create,
update, complete, reopen and delete therefore share the closed lifecycle
contract while the established journal, ledger, cloud protocol and UI remain
unchanged. The legacy tombstone payload is retained only at the persistence
adapter boundary.

**Planned architecture:** The Task Engine owns task lifecycle, state transitions, scheduling intent, priority projections, and stable persistence semantics. A task is not a calendar reservation until planning and confirmation convert it into one.

### 7.10 Shopping Engine

**Current state (V1-SH.1):** Shopping items have a model, local/cloud
persistence, conversational creation, grouping metadata, and dedicated UI. A
pure, versioned item-lifecycle boundary now validates add, update, mark bought,
mark needed and remove with stable identity, explicit revision and preserved
clear generation. It forbids hiding bought-state changes inside a generic
update and emits no item content for a removal. Collection-wide clear remains
a separate future contract. SH.2 now routes production add and reconciliation
decisions through SH.1 before creating the existing revisioned mutation. Add,
update, mark bought, mark needed and remove share the closed lifecycle contract
while the journal, ledger, cloud protocol and UI remain unchanged. The legacy
tombstone payload is retained only at the persistence adapter boundary.

**Planned architecture:** The Shopping Engine owns shopping-item lifecycle, normalization, grouping, and future context-aware assistance. It remains distinct from general tasks even when both originate in one message.

### 7.11 Notification Engine

**Current state:** V1-N.1 provides local-only permission, private scheduling
and safe navigation. V1-N.2 produces four deterministic, evidenced signal
families. V1-N.3 applies one account-scoped product policy to category
activation, pause, quiet hours, daily limits, important product alerts and a
bounded daily summary. Permission is never requested during bootstrap and
system content remains generic.

**Planned architecture:** The Notification Engine owns notification intent, authorization, scheduling identity, delivery policy, cancellation, and truthful failure reporting. Notifications are consequences of domain decisions, not a competing source of business truth.

## 8. Engine interactions

Engines cooperate through explicit projections rather than shared hidden assumptions.

```text
User interaction ─→ Conversation Engine ─→ typed conversation state ─┐
                                                                    ├─→ Reasoning ─→ conversational explanation
Profile ───────┐                                                    │
Memory ────────┼─→ Life Context projection ─────────────────────────┘
Routines ──────┘          │
                          ├─→ Planning ─→ confirmed calendar events
                          ├─→ Priority ─→ ranked tasks and suggestions
Tasks ────────────────────┤
Shopping ─────────────────┤
Calendar ─────────────────┘

Conversation Engine ─→ typed domain workflows

Confirmed domain changes ─→ Notification
```

This diagram describes planned ownership, not a claim that a standalone Conversation, Life Context, or Reasoning Engine is already implemented.

Interaction rules:

- Profile and memory may both describe context, but the user's current instruction overrides both.
- Memory-derived routines may block planning only when they produce a complete, applicable structured constraint.
- Priority may recommend what deserves attention but cannot reserve time without the planning lifecycle.
- Task and shopping actions may be created from one conversational response but retain separate domain persistence and behavior.
- Notification follows successful domain operations and must not be used as evidence that persistence succeeded.
- The AI layer may explain engine results but cannot override them.
- The Conversation Engine owns workflow state, not domain truth or Life Context facts.
- The Reasoning Engine consumes typed conversation state and Life Context projections without replacing deterministic domain engines.

## 9. Conversation and action lifecycle

### V1-A.1 — Central autonomy policy

`ActionAutonomyPolicyEngine` is the single deterministic authorization matrix
for the three account-scoped modes. `normal` allows explicit, grounded and
complete requests while preserving every domain confirmation. `suggestions`
allows reads and proposals but requires a fresh explicit confirmation before
every mutation. `paused` keeps conversation and permitted reads available,
while blocking proposals intended for execution, confirmations, mutation
retries and pending execution. The restrictive default is `suggestions`.

The closed inputs are action type, technical origin, registered risk, C.3
grounding/completeness, domain policy, confirmation, conflict, pending state
and session generation. Proactive, external and unknown origins are always
blocked. Risk is registered by action type and never inferred from visible
text or a person. The guard order is: account/session, response generation,
supported type, C.3 grounding, required fields, stale/contradiction, domain
policy, A.1 mode, confirmation, conflict/revision, idempotence, then domain
dispatch. The most restrictive result wins.

The local `ActionAutonomyPolicyService` persists one versioned value under an
account-scoped SharedPreferences key. Corrupt or missing state falls back to
`suggestions`; no Firestore collection or multi-device synchronization is
claimed. A same-UID account link retains the setting, while an account change
loads a distinct key. The settings screen calls only this service.

`ActionPending` is the sole generic A.1 continuation for simple conversational
mutations. Its payload is a closed Task or Shopping value rather than a
business `Map`; it carries generation, action type, origin, risk, mode and
policy version at creation, bounded original instruction, mutation identity,
grounding/completeness, expiry, fresh-confirmation state, bounded attempts and
the pending state machine. In Suggestions the coordinator creates this value
after C.3, writes nothing, and executes only after reloading and re-evaluating
the current policy. Pause marks it `blockedByPolicy` without deleting it.
Changing mode never executes it; a new explicit confirmation is required.

Smart Planning continuations carry the same A.1 mode/version/type/origin/risk
metadata and their final mutation identity. Policy is reloaded when resolving
each continuation, before an executable confirmation and twice around final
Event revalidation/dispatch. Searches and bounded alternatives remain
read-only in Pause, but reservation is blocked and the typed continuation is
preserved. Identity selection and creation are classified as sensitive and
revalidated immediately before their application service. Account change
clears generic, Event, Memory and Identity pending state and invalidates Smart
Planning.

`ChatBackendRequest` sends only the policy version, current mode and the closed
response kinds allowed for that mode. Functions validates these fields and
rejects structured actions in pause before model output can reach Flutter.
Flutter remains authoritative and re-evaluates the current policy after the
backend response. `ChatScreen` owns no matrix or storage access.

Memory actions remain subject to the stricter combination of A.1,
`MemoryPolicy`, health consent and memory confirmation. Event and Smart
Planning keep their date, duration, travel, margin, conflict, revision,
mutation-id and confirmation guards. A.1 introduces no proactive execution,
notification, third-party action, ledger, replay or undo; those remain outside
this phase.

### 9.1 Current state

The Flutter chat experience follows the C.1 chain:

`ChatScreen → ConversationSessionController → ConversationCoordinator →
ConversationContextProvider → ChatBackendClient`.

The provider remains the only request/context construction dependency and
preserves the LC.3 compatibility boundary. The callable client remains an
injectable gateway. `ConversationCoordinator` applies the existing guards and
delegates only validated actions. `ConversationLegacyActionExecutor` keeps the
legacy Task, Shopping and Event application path outside the widget while the
domain services continue to own persistence and confirmation. When a Task
creates the historical Smart Planning prompt, the executor starts a typed
continuation instead of retaining a free-form map.

The public session state contains only a random technical session identifier,
bounded visible messages, phase, recoverable error copy, pending presence and
one-shot effects. It contains no UID, account scope, request payload, snapshot,
graph, repository, exception or stack trace.

The active remote AI boundary is the single Firebase callable
`chatWithZeliaCallable`. It requires a Firebase Auth UID, including an anonymous
UID, and derives identity only from verified callable context. The historical
HTTP transport is no longer exported or present in the Flutter client.
The callable validates a closed request before quota consumption, rejects
client-controlled identity fields, and validates a closed response capped at
64 KiB before returning it. Flutter applies the same response-size bound and
fails closed on unknown, absent or malformed contract fields. There is no
automatic HTTP fallback.

Before OpenAI execution, a transaction consumes a technical quota from one
deny-by-default Firestore document per UID. It stores no conversation content.
Its bounded settings are `ZELIA_AI_CHAT_QUOTA_LIMIT` and
`ZELIA_AI_CHAT_QUOTA_WINDOW_SECONDS`; it is not a commercial entitlement model.
Quota storage failure is fail-closed and the verified callable UID is the only
quota identity.

### 9.1.1 V1-S0.1 security environments and App Check

The security environment is closed and never comes from the chat payload.
Flutter accepts only `emulator`, `debug`, `staging` and `production`; an unknown
release value fails closed to production and a release build cannot select
debug or emulator. Functions accepts only `development`, `staging` and
`production`, plus the Functions emulator signal; an unknown server value is
reported as production.

| Environment | Required controls |
| --- | --- |
| Local development / personal device | Firebase Auth, closed request/response validation and server quota remain mandatory. App Check enforcement may temporarily be disabled when the Personal Apple Team cannot provision App Attest. A missing token emits only the closed `app-check-not-enforced` diagnostic; it never weakens another control. |
| External beta / TestFlight | A compatible Apple Developer team, registered App Attest application, valid signed-build token and enabled App Check enforcement are release gates. Debug providers are forbidden. |
| Production | App Check enforcement is mandatory, debug providers and the legacy HTTP endpoint are forbidden, and `OPENAI_API_KEY` remains a Firebase Secret Manager secret available only to the callable. |

The currently tracked Firebase parameter file is explicitly labelled
`development` and keeps App Check enforcement disabled for the validated
personal-device workflow. It is not a beta or production configuration.
Before TestFlight, the release owner must change the server environment to
`staging`, enable `ZELIA_ENFORCE_APP_CHECK`, configure the Apple Developer team
and App Attest registration, then verify a signed build before external access.
Production repeats those gates with the `production` environment.

The former `chatWithZeliaHttp` export is absent from the repository and
architecture tests prevent its reintroduction. Its remote deployment state is
not inferable from local files. If a remote inventory confirms it still exists,
it must be deleted separately after explicit approval:

```sh
firebase functions:delete chatWithZeliaHttp \
  --region us-central1 \
  --project zelia-ai-app
```

No remote deletion is part of V1-S0.1 implementation or validation.

Provider diagnostics are allow-listed technical records only: correlation ID,
component, step, closed code, environment, model/tier, bounded counts/status and
duration. User messages, history, memories, profile data, task/event content,
provider responses, Auth/App Check tokens and secrets are never diagnostic
metadata. Repository architecture tests scan production Flutter and Functions
sources for direct OpenAI transport, embedded provider keys, Bearer credentials
and additional callable seams.

### 9.2 C.1 lifecycle and remaining boundaries

Each submit receives un `requestId` et la génération courante de session. Une
réponse n’est appliquée que si les deux correspondent encore. Annulation,
dispose ou changement de compte incrémentent la génération : une réponse
tardive ne peut alors ni ajouter de message ni exécuter une continuation.
Le retry backend est limité à une tentative et ne recrée pas le message
utilisateur. L’annulation reste logique : elle ne promet pas d’interrompre le
callable déjà parti.

Les continuations Smart Planning restent volontairement en mémoire : elles
survivent aux rebuilds de l’écran parce qu’elles appartiennent au contrôleur,
mais pas au redémarrage du processus. Elles expirent après deux heures, sont
invalidées lors d’un changement de compte ou de génération, et sont nettoyées
après succès, refus ou expiration. Un `mutationId` technique protège l’action
finale contre une double confirmation.

La preuve d’équivalence couvre les anciens parcours : consentement de
planification, validation de durée, trajets aller/retour, demande explicite de
créneau, choix parmi trois options, récapitulatif, revalidation avant écriture,
alternative après conflit et recherche par tranches bornées de quatorze jours.
Les marges, périodes protégées et conflits continuent d’être calculés par les
services Planning existants.

Les erreurs backend sont transformées par le catalogue sûr existant et seuls
code, étape, retryabilité et corrélation technique sont diagnostiqués. Les
messages sont persistés derrière `ConversationMessageStore`; l’écran ne connaît
pas cette persistance.

### 9.3 C.2 — Contexte conversationnel borné

Le parcours de production utilise désormais une seule chaîne multi-domaines :
`LifeContextProductionFactory → LifeContextProjectionEngine` avec le contrat
Conversation LC.3, puis `ConversationContextAssembler → ChatBackendRequest`.
Le contrôleur demande cette frontière injectable; ni l’écran ni le contrôleur
ne chargent un repository. L’ancien adaptateur de compatibilité dérive lui
aussi son résultat du même assembleur et n’est donc pas un second builder.

L’enveloppe `conversation.transport.v1` conserve l’état `complete`, `partial`,
`stale` ou explicitement indisponible, la disponibilité et la fraîcheur par
section, les budgets LC.3, les omissions et les troncatures. Elle ne sérialise
ni UID/scope, ni snapshot, graphe, profil, `MemoryContext`, provenance source,
révision métier ou contenu Priority. Un échec de projection produit un état
fermé; il n’est jamais transformé en contexte complet composé de listes vides.

Le transport applique en plus des bornes déterministes : message courant
4 000 caractères et 12 000 octets UTF-8, historique de 8 messages au maximum
(1 000 caractères chacun, 8 000 octets au total), contexte 24 000 octets et
requête complète 48 000 octets. Le message courant est refusé, jamais tronqué
silencieusement. L’historique est limité aux rôles utilisateur/assistant,
ordonné et dédupliqué; le parcours actuel n’envoie pas encore d’historique
ancien par défaut. Les alias backend historiques restent présents mais vides
et sont comptés dans la taille finale.

La redaction version 1 est une allowlist des sections et faits LC.3. Santé,
médical, adresse complète, téléphone, secrets, tokens, documents bruts,
tombstones, conflits et file mémoire restent interdits. Les mémoires ne
proviennent que de la section Memory LC.3, donc après politique, consentement,
cycle de vie, déduplication canonique et budget. `memoryReasoning` n’est plus
une seconde copie : son alias de transition est vide.

Flutter valide version, finalité, clés, états, budgets, nombres d’éléments,
tailles de texte et taille UTF-8 avant le callable. Functions répète cette
validation avec une allowlist fermée et une redaction finale avant le builder
de prompt; une requête invalide n’atteint ni quota ni modèle et aucune erreur
ne contient le payload. Le prompt existant consomme seulement les sections
sanitisées et leurs marqueurs de disponibilité, sans changer personnalité,
modèle, routage ou politique d’action.

La construction LC est bornée à sept secondes; annulation, retry, changement
de génération et changement de compte continuent d’utiliser les protections
C.1. Un retry reconstruit le contexte depuis le scope Auth courant. Les
continuations Smart Planning restent typées et ne dupliquent pas ce contexte.

C.2 ne branche pas Priority, ne change ni modèle OpenAI ni politique d’action
et n’ajoute aucun nouveau prompt général.

### 9.4 C.3 — Grounding, incertitude et clarification

La réponse callable possède désormais un contrat épistémique version 1 fermé.
Il distingue `grounded`, `groundedPartial`, `uncertain`, `conflicting`,
`stale`, `contextUnavailable`, `insufficientInformation`, `unsupported` et
`invalid`. Les types de réponse sont eux aussi fermés : réponse, réponse
prudente, clarification ou confirmation requise, proposition ou résultat
d’action, impossibilité de déterminer, contexte indisponible, demande non
supportée et échec sûr.

Une affirmation personnelle est déclarée comme claim structuré. Chaque claim
référence au plus trois entrées de grounding et chaque référence doit pointer
vers le message courant, un message historique validé, une clarification ou un
résultat confirmé, ou vers un fait effectivement présent dans l’enveloppe C.2.
`generalKnowledge` autorise une réponse générale mais ne peut soutenir ni claim
personnel ni action. Les références ne transportent ni valeur personnelle, ni
UID/scope, ni chemin source. Functions vérifie leur existence dans l’enveloppe
réellement envoyée et Flutter répète cette validation avant le coordinateur.

`ConversationGroundingPolicy` est la frontière pure et unique qui décide entre
réponse directe, réponse prudente, clarification, refus d’action,
`cannotDetermine` et retry du contexte. Elle reçoit des informations
manquantes et contradictions typées; elle ne lit aucun repository, n’appelle
ni Firebase ni OpenAI et n’écrit aucun domaine. Une absence reste distincte
d’une négation. Une section indisponible ne devient pas une section vide et une
source stale ne peut pas être présentée comme current.

Les clarifications portent une raison, un type de réponse, des choix bornés,
les champs manquants, la génération de session, une expiration éventuelle et
un numéro de tentative. Le contrôleur conserve un registre par génération :
trois tours au maximum et aucun code de champ identique redemandé. Lorsque la
limite est atteinte, il rend une formulation française sûre et n’exécute
aucune action. Annulation, changement de compte et dispose invalident aussi ce
registre.

Une clarification Event peut transporter un
`ConversationClarificationDraft.eventCreation` fermé. Ce payload est un état
conversationnel non exécutable : `actions` reste vide, aucune autonomie ni
persistance n’est déclenchée, et aucun identifiant de compte ou de mutation
n’est exposé. Le contrôleur Flutter l’enregistre uniquement pour la génération
active et l’exécuteur de continuation recueille durée, trajets et marge avant
de construire un Event complet. Le draft expire après quinze minutes et est
invalidé au changement de compte, au refus, au succès ou à l’expiration.

Functions valide la structure fermée, les bornes, les sources, claims,
informations manquantes, contradictions et clarifications après le modèle mais
avant tout retour client. Une action Event exige date, heure et durée positive,
ainsi que les deux trajets lorsqu’ils sont déclarés séparés. Task et Shopping
n’inventent aucune échéance, durée, priorité ou quantité facultative. Une
information obligatoire manquante ou une contradiction bloquante interdit
toute action. Un `actionResult` exige une source métier confirmée.

Le guard Flutter applique le même invariant avant la boucle d’actions de
`ConversationCoordinator`. Une réponse invalide n’atteint donc jamais les
services Event, Task, Shopping, Routine, Identity ou Memory. Les continuations
Smart Planning C.1 gardent leur machine d’états typée, leurs trajets, marges,
conflits, confirmations et revalidations.

Le prompt est seulement complété par les obligations C.3 : aucune invention de
fait personnel, déclaration des manques et contradictions, distinction entre
connaissance générale et situation personnelle, et absence de faux succès. Le
modèle, le routage Luna/Terra/Sol, les budgets C.2 et la personnalité ne
changent pas. A.1 reste hors de cette frontière et définira séparément les
modes d’action.

The durable lifecycle is:

1. Establish a valid user identity without forcing visible registration.
2. Build a bounded request from current user input and authorized context.
3. Send it through an authenticated, application-attested, validated backend boundary.
4. Receive a strictly structured response.
5. Validate every proposed action deterministically.
6. Resolve missing information through typed workflow state.
7. Revalidate mutable facts such as calendar availability.
8. Obtain explicit confirmation for consequential operations.
9. Persist through the authoritative domain repository.
10. Report actual success or a safe failure.

Requests that may produce actions must not be retried automatically unless end-to-end idempotency exists.

## 10. Identity, data, and synchronization lifecycle

### 10.1 Current state

- Visible account creation is optional.
- Signed-out users can use locally persisted profile, task, shopping, and calendar features.
- Memory and conversation persistence require a Firebase UID.
- Local persistence keys are installation-scoped rather than identity-scoped.
- Email account creation and sign-in do not link or reconcile a prior temporary identity.
- Cloud task, event, and shopping synchronization currently treats a non-empty cloud dataset as authoritative and may upload local data when cloud data is empty.
- Firestore access is restricted to the authenticated user's UID subtree.

### 10.2 Planned architecture

- Every active ZELIA session has a Firebase identity when identity services are available.
- A user without a permanent account receives an anonymous identity and immediate access.
- Creating a new permanent account links credentials to the anonymous user so the UID remains stable.
- Signing into an existing permanent account follows an explicit, restart-safe reconciliation process.
- Local caches are identity-scoped and cannot leak across sign-out or account changes.
- Data reconciliation has explicit ownership, conflict, deletion, and completion semantics.
- Anonymous-auth failure preserves safe local features but does not fall back to an unrestricted AI endpoint.

No implementation may silently copy one user's local or cloud data into another UID.

### 10.3 Universal human model foundation

`HumanModel` is the canonical V1 foundation for human situations. It is a
versioned, account-scoped aggregate containing stable person references,
directional relationships, households, residences, household memberships, and
organizational responsibilities. Relationships, memberships, residences, and
responsibilities support explicit validity periods; provenance and confirmation
are carried by `HumanEvidence`.

Ownership is deliberately separated:

- Identity owns the stable identity of a person or other entity. A
  `HumanPerson` may reference a confirmed `PersistedIdentityLink`, but the human
  model never creates, merges, or deletes an Identity.
- the human model owns known human relationships, household membership,
  residence association, and organizational responsibility;
- Life Context may later project consequences and cross-domain dependencies. It
  does not own or mutate the human aggregate, and HM.1 does not extend it.

Schema version 1 is stored locally under
`human_model_v1:{accountScopeId}`. On the first authenticated profile load,
`HumanModelService` migrates the legacy `UserProfile`, validates and persists
the complete candidate, then reads it back. A later load always uses the
persisted aggregate, making migration idempotent. Failure leaves the legacy
profile untouched and usable. A future schema version or corrupt aggregate is
an explicit failure, never an empty successful model.

Legacy migration is intentionally conservative:

- the main profile becomes one stable person only when a stable account scope
  exists;
- a non-empty `partnerName` creates one unlinked, non-gendered partner candidate
  marked `legacyProfile` and `needsConfirmation`;
- every `ChildProfile` creates a distinct unlinked person and a directional
  child relation, also requiring confirmation;
- marriage, cohabitation, biological relation, custody, a shared household,
  residence, legal responsibility, gender, and inverse relations are never
  inferred;
- the complete legacy payload, including fields not yet projected, remains in
  the aggregate for compatibility and rollback. Legacy storage is not deleted.

Canonical JSON is deterministic, preserves unknown top-level fields for
forward-compatible reads, and rejects invalid references, duplicate records,
invalid periods, cross-account content, corrupt input, and unsupported future
versions. Diagnostics contain only stable technical codes and migration steps;
they never contain names, relations, residences, profile JSON, Identity data,
or account IDs.

HM.2 promotes the aggregate to a private, shared source of truth at
`users/{uid}/private/humanModel`. The cloud document is a single bounded
snapshot (maximum client payload 700,000 UTF-8 bytes) with schema version,
monotone `modelRevision`, immutable account scope, server timestamps,
idempotent non-personal `lastMutationId`, migration version/status, and a
validated deterministic payload. A transaction creates only when absent or
updates exactly `N → N+1`; a stale writer receives a conflict and cannot
overwrite the winner.

Bootstrap uses this order:

1. validate the last local envelope, falling back to its single previous
   snapshot if the current value is corrupt or unsupported;
2. read the authenticated account's cloud document;
3. adopt and locally verify a valid cloud model when present;
4. otherwise upload the exact HM.1 local graph with its existing IDs;
5. otherwise migrate the retained `UserProfile` and create the cloud document
   only if it remains absent;
6. if two devices race, the losing device reloads and adopts the winning cloud
   graph;
7. when offline, retain the last valid local model with an explicit unsynced
   status rather than claiming cloud success.

The local key remains `human_model_v1:{accountScopeId}` but now stores a
versioned envelope: current model, known cloud revision, sync and migration
states, last mutation, and at most one pending canonical mutation. Before
replacement, the repository saves one previous valid envelope; it writes,
reads, and validates the candidate before success. The legacy HM.1 raw-model
format remains readable. Neither the previous envelope nor `user_profile` is
deleted during migration.

Legacy compatibility IDs (`humanPersonId` on the principal and each child,
plus `partnerHumanPersonId`) are optional additive JSON fields. They are random,
hidden from UI, never derived from names, and reused when already present. The
canonical payload retains the enriched legacy snapshot. Reconciliation may
update the legacy payload and an unconfirmed legacy principal deterministically;
partner replacement, missing children, renames without stable correspondence,
deletions, and other ambiguous changes become one bounded pending proposal and
never mutate the cloud silently. Confirmed canonical data always wins over an
ambiguous legacy value.

Firestore rules now give `private/profile` its historical owner-only access and
give `private/humanModel` a stricter shape/revision lifecycle. Authentication,
path UID, `accountScopeId`, payload scope, schema, initial revision, exact
increment, immutable creation metadata, and direct-delete denial are enforced.
Anonymous Firebase sessions are accepted because they have a verified UID;
credential linking preserves the same scope.

`UserProfile` remains the compatibility view and the source for fields not yet
migrated. ProfileScreen, onboarding, conversation, planning, and Life Context
still consume it during HM.2. HM.2 does not add family-management UI or send the
human graph to OpenAI. HM.3 must provide explicit canonical editing and
user-facing reconciliation before replacing those legacy views. A future
partitioning phase is required before the bounded single-document payload
approaches its limit.

HM.3 adds that explicit user-facing boundary. `HumanModelEditService` is the
single application service used by the profile flow: it loads the local
revisioned envelope, applies one typed model transformation, validates the
complete aggregate, generates a non-personal mutation ID, and delegates the
revision-checked write to `HumanModelService.saveCanonical`. Its closed result
distinguishes validation, revision conflict, offline pending synchronization,
network, storage, cancellation, and unknown failures. Screens never access
Firestore or SharedPreferences and never display revisions, scopes, or mutation
IDs.

`HumanProfileScreen`, reached from the existing Profile screen through “Mon
organisation”, provides progressive sections for the main person, other
persons, relationships, households and memberships, residences,
responsibilities, and retained legacy proposals. Empty sections are valid.
Records are archived, ended, or detached rather than cascaded. Forms never
require gender, marriage, children, an address, one household, or one
responsible person, and they never create or delete Identity records.

Legacy proposals can be confirmed, rejected, or postponed. Rejection stores a
bounded deterministic technical marker in the retained legacy snapshot so the
same unchanged proposal does not return; source changes create a new proposal.
No proposal content appears in diagnostics. `HumanModelUserProfileProjectionService`
updates only the deterministically mapped main person, partner, and child names
while preserving all other legacy and unknown fields. Ambiguous partners,
relationships, family status, custody, and households never overwrite
`UserProfile`.

The initial onboarding now ends after an optional display name and explicitly
offers “Je préfère compléter plus tard”. Historical family, partner, child, and
work screens remain readable compatibility code but are no longer required to
start Zélia. The complete human organization is edited later through the
canonical flow. HM.3 does not project the graph to OpenAI, alter planning,
derive custody consequences, or start Life Context work.

## 11. Persistence principles

1. Persisted identity must be stable and explicit.
2. Local availability must not weaken cloud ownership boundaries.
3. Empty remote data must not be interpreted as migration permission without context.
4. Deletes must remain deletes unless an explicit recovery operation restores them.
5. Synchronization must be idempotent and bounded.
6. Stored records require stable identity appropriate to their domain.
7. Schema evolution must preserve readable legacy data or provide an approved migration.
8. A cache is not automatically a source of truth.
9. Sensitive profile and memory data must remain user-owned and minimally exposed.
10. Persistence outcomes must be observable to their callers.

## 12. Planning invariants

These invariants are constitutional because they protect user trust:

- Missing date, time, duration, travel, or recurrence details are not invented.
- A proposal is not persisted before confirmation.
- Confirmation is explicit and belongs to the active proposal.
- Appointment time and protected time are distinct concepts.
- Outbound travel, return travel, explicit zero values, and safety margins are preserved.
- Conflict checks use complete protected ranges.
- Selected slots are revalidated before creation.
- Structured hard constraints block; preferences influence ranking.
- Recurrence applies only on matching dates and valid anchors.
- Legacy stored events remain readable.
- Changes to scoring or planning windows require behavior-focused regression tests.

## 13. Memory invariants

- Only durable information is eligible for durable memory.
- An absent policy is restrictive: confirmation is required and health is
  disabled.
- General consent never grants health consent.
- Pause creates no proposal or memory and causes no retroactive ingestion.
- One-off actions do not become memory merely because they contain important words.
- Memory persistence must be successful before success is claimed.
- Exact and semantic duplicate policies must remain distinguishable.
- Memory context is bounded and selected through an explicit relevance policy.
- Stored creation metadata is preserved when recurrence depends on it.
- Free memory never enters Planning. Only the explicit legacy-routine
  compatibility bridge may produce complete, applicable recurring constraints.
- Users must ultimately be able to inspect, correct, and delete durable memories.
- Consolidation must preserve provenance and must not erase conflicting facts silently.
- Client and server memory responsibilities require an explicit authority contract.

## 14. AI and model principles

The AI layer is replaceable infrastructure behind stable product contracts.

- Model selection may vary by intent and complexity without changing application behavior contracts.
- Prompts express conversational policy but do not own persistence or security.
- Generated responses use a strict schema.
- Strict server output does not eliminate the need for client validation.
- Model fallbacks are bounded and must not recurse indefinitely.
- AI requests should include only the context needed for the task.
- Private context and raw errors must not be placed in uncontrolled logs.
- Timeouts and failure handling are explicit.
- Action-producing requests are not automatically replayed without idempotency.
- Model names, providers, and routing tiers are configuration details, not constitutional architecture.

## 15. Security and privacy principles

Security is layered:

1. **Identity** establishes who is acting.
2. **Application attestation** helps establish that the request comes from an approved client.
3. **Request validation** bounds and validates all untrusted input.
4. **Authorization rules** constrain access to user-owned data.
5. **Domain validation** prevents invalid actions even from structurally valid input.
6. **Confirmation** protects user intent.
7. **Bounded execution** limits time, payloads, retries, and cost.
8. **Safe observability** records operational facts without exposing private content.

### Current state

Firestore data is UID-owned and deny-by-default outside the user subtree.
Storage is deny-all. The OpenAI secret is held by the Functions environment.
The callable AI boundary requires Firebase Auth, production App Check, strict
request validation and a transactional server quota. It has no HTTP fallback.

The client Firestore boundary is also deny-by-default inside
`users/{uid}`. Every supported subcollection has an explicit matcher; an
unknown descendant, a root user write, and every server-only root collection
are denied. The UID in the path is the ownership authority. Where a persisted
contract also contains `accountScopeId`, it must equal that path UID and remain
immutable. Revisioned entity IDs remain equal to their document IDs.
Conversations and memory-replacement actions use closed schemas rather than a
generic authenticated-user fallback.

Local compatibility state is separated between guest storage and
UID-qualified storage. Profile compatibility snapshots, Event caches and
sync journals, dashboard photo references, revisioned repositories,
conversation references, proactive receipts and policies use the active
account scope. Event guest state uses an explicit `guest` scope; historical
global Event and sync-journal keys are never imported into either a guest or an
authenticated account because their ownership cannot be proven. A Firebase
Auth UID transition clears visible profile and Agenda state, invalidates
in-flight Event loads, and rebuilds `MainNavigation`, which disposes
conversation continuations and listeners from the previous account before
loading the next scope. A queued Event mutation is rejected when its recorded
account differs from the active journal scope.

### Planned architecture

The AI boundary uses Firebase Authentication, anonymous authentication for
immediate use, callable Functions, production App Check, strict request
validation, a transactional server quota, bounded errors and timeouts, and no
unrestricted fallback endpoint.

Firebase project, database, region, provider, enforcement, secret, and deployment changes always require explicit approval and current-state verification.

### Diagnostic and error policy

**Current state (V1-S0.4):** Flutter and Functions use one closed diagnostic
boundary per runtime. Production, staging, debug and emulator are explicit
environments, but none of them may log user content. Diagnostics are
deny-by-default and versioned. A record contains a random diagnostic ID, the
bounded correlation ID, component, domain, operation, step, stable code,
severity, retry strategy, timestamp, environment, a closed technical status
and explicitly allowlisted scalar metrics. Arbitrary objects, exception
messages and stack traces are never serialized.

Conversation text, prompts, model responses, memories, profiles, events, tasks,
shopping data, documents, names, contact details, addresses, birth dates,
health data, Firebase UIDs, Auth/App Check tokens, credentials, secrets, request
bodies and Firestore documents are forbidden in logs in every environment.
Debug and emulator may provide additional technical scalar metadata only; they
do not relax the content policy. Test fixtures remain synthetic. Exception
types are reduced to an allowlist; `toString()` is never a diagnostic source.

The shared error taxonomy distinguishes authentication, authorization,
validation, contract, quota, network, timeout, dependency/provider,
configuration, conflict/stale revision, stale asynchronous result, account
scope mismatch, local persistence, synchronization and internal failure.
Severity is one of `info`, `warning`, `recoverableError` or `criticalError`.
Retry is one of `notRetryable`, `retryImmediately`, `retryWithBackoff`,
`retryAfterUserAction` or `retryAfterReauthentication`. A refusal or normal
absence is not a technical failure. User messages are mapped centrally and do
not claim local durability unless the caller has selected the explicit
`sync-pending` result after a proven durable local write.

`main.dart` installs framework, platform and guarded-zone boundaries before
Firebase initialization. A startup failure records only its closed
classification and renders a minimal fallback instead of a blank screen.
Failure of a sink, local store or future remote reporter is ignored without
recursion and never replaces the original exception.

Flutter keeps at most 100 sanitized diagnostics and 256 KiB in a versioned
local buffer with rotation, one-minute duplicate suppression, backup recovery
and corruption tolerance. The buffer contains no UID and is therefore safe
across account changes; it cannot be used to reconstruct account activity.
`ApplicationHealthSnapshot` exposes only closed startup/dependency/account
states, bounded mutation counts and age buckets. `RevisionedMutationHealthService`
maps durable journals to retry scheduled, conflict blocked, invalid payload,
account mismatch, permanent failure and completed counts without exposing
mutation or entity identifiers.

The chat request carries one 32-character random correlation ID. The callable
validates it as part of the closed request, propagates it through routing,
provider diagnostics and transport failure, and returns no private context in
it. A retry of the same logical request reuses the correlation ID; a
`mutationId` remains a separate idempotency identity.

No analytics or crash-reporting SDK is installed by S0.4. The
`AppCriticalDiagnosticReporter` boundary is inert unless a future approved
provider is injected. Before external beta, the team must choose and configure
that provider, verify consent and retention, connect only sanitized records,
test fatal/non-fatal delivery on signed builds, and document operational
ownership and deletion. Runtime logs and the bounded local buffer do not
provide a remote incident dashboard or long-term retention.

## 16. Testing and quality model

ZELIA uses layered confidence:

- unit tests protect deterministic rules;
- contract tests protect client/server structures;
- workflow tests protect multi-step user behavior;
- repository tests protect persistence and synchronization semantics;
- security-rule and backend-boundary tests protect authorization;
- platform tests protect integrations such as authentication and notifications;
- manual validation covers experiences that cannot be proven locally.

Tests must focus on outcomes and invariants, not merely reproduce implementation structure. A behavior is not considered protected when only an isolated helper is tested but the live execution path is not.

No test may be reported as passing unless it was executed successfully in the current work. Environmental limitations must be reported explicitly.

### Mobile baseline

The supported V1 mobile clients are iPhone, iPad, and Android phones. The
verified local baseline uses Flutter 3.41.9, Dart 3.11.5, Xcode 26.5,
CocoaPods 1.16.2, Android SDK 36, Android Gradle Plugin 8.11.1, Gradle 8.14,
Kotlin 2.2.20, and JDK 17. iOS has a deployment target of 15.0 and supports
device families 1 and 2. Android has minSdk 24 and compileSdk/targetSdk 36.

Local validation uses:

- `flutter build ios --simulator` for unsigned iPhone and iPad simulator code;
- `flutter build ios --release --no-codesign` for an unsigned device release;
- `flutter build apk --debug`, `flutter build apk --release`, and
  `flutter build appbundle --release` for Android artifacts;
- Firebase Emulator plus `ZELIA_FIREBASE_ENVIRONMENT=emulator` for mobile smoke
  tests that create an anonymous Firebase session without touching remote data.

Debug Android alone permits clear-text loopback traffic to the local Firebase
Emulator. Release builds do not inherit that exception. Debug App Check uses
the official debug providers, emulator mode omits App Check only for local
emulators, and staging/production use platform attestation providers. Remote
provider registration and enforcement remain a controlled deployment step.

The current native permissions are deliberately limited. Android declares
network, microphone, notification, vibration and boot-rescheduling access;
its package-visibility query is limited to the system speech recognition
service;
gallery selection uses the modern system picker and no exact-alarm, broad
storage, camera, location or contacts permission is requested. iOS declares
microphone, speech-recognition and photo-library usage; notification permission
is compiled, as are the microphone and speech-recognition permission handlers,
but each native prompt follows an explicit explained user action. No
background-audio mode is enabled. Distribution
signing and physical-device release validation remain deferred; local release
validation does not require a paid Apple Developer membership.

## 17. Architectural decision framework

Architectural decisions should be evaluated in this order:

1. Does the decision preserve user trust and explicit control?
2. Does it preserve security and data ownership?
3. Does it preserve existing behavior and stored-data compatibility?
4. Does it clarify or weaken source-of-truth ownership?
5. Can it be introduced through a small, testable seam?
6. Does it reduce duplicated business rules?
7. Can failure be detected and explained safely?
8. Is the operational cost and rollback path understood?

Major decisions require a dedicated decision record when they change identity, persistence, security, domain ownership, public schemas, or irreversible product behavior.

## 18. Architectural decision register

This register records durable decisions and declared directions, not every implementation choice.

| Decision | Status | Rationale |
|---|---|---|
| Flutter is the primary client application architecture | Current state | The active product and deterministic client domains are implemented in Flutter |
| Firebase is the identity, cloud data, and serverless backend platform | Current state | Authentication, Firestore, Functions, Hosting, and Storage configuration exist |
| AI output is untrusted and strictly structured | Accepted | Generated language cannot directly authorize side effects |
| Consequential calendar operations require explicit confirmation | Accepted | Protects user intent and prevents fabricated authorization |
| Planning uses complete protected ranges | Accepted | Availability must include travel and margin, not only appointment time |
| Existing stored data remains backward compatible | Accepted | User data must survive schema evolution |
| ZELIA remains usable without visible account registration | Current state | Anonymous Auth preserves immediate usefulness |
| Anonymous Firebase identity protects nonregistered sessions | Current state | Enables UID ownership without forced registration |
| The AI boundary uses protected Firebase-native callable access | Current state | Auth, App Check, quota, and validation address different abuse risks |
| App Check is enforced outside the explicit local emulator | Current state | Debug tokens remain a controlled development mechanism |
| A typed Conversation Engine is extracted before new shared engines | Planned architecture | Stabilizes interaction and action lifecycle state without moving domain truth into the conversation layer |
| Life Context becomes the first shared authoritative context projection after the conversation boundary exists | Planned architecture | Reduces duplicated interpretation across planning, priority, and reasoning without owning conversational state |
| Reasoning consumes typed conversation state and typed Life Context projections | Planned architecture | Multi-domain reasoning depends on both inputs and must not replace deterministic domain engines |

## 19. Known architectural debt

Architectural debt is recorded here to prevent accidental normalization. It does not authorize unrelated refactoring.

### High priority

- App Check providers and enforcement must be configured in every remote
  Firebase environment before release; checked-in code fails closed but does
  not alter remote Firebase configuration.
- Legacy guest-only caches remain intentionally separate from authenticated
  UID caches; any future guest-to-account merge still requires an explicit
  product reconciliation policy.
- Cloud list synchronization has ambiguous empty-cloud and full-replacement behavior.
- Recurring calendar series require a complete conflict policy across all occurrences.
- The chat screen owns too many workflow responsibilities, and no typed Conversation Engine yet owns active interaction, interruption, cancellation, and action lifecycle state.

### Medium priority

- Memory persistence does not expose a reliable success result to conversation orchestration.
- Memory correction and deletion flows are incomplete.
- Relevant-memory selection and advanced similarity/consolidation do not yet have one live authoritative policy.
- Natural-language date, time, duration, and recurrence parsing responsibilities are distributed.
- Priority behavior lacks a complete public contract and focused coverage.
- Large profile and primary feature screens combine substantial state and rendering responsibilities.
- End-to-end conversation, synchronization, authentication, and Firebase-rule coverage is incomplete.

### Deferred or conditional

- Apparently unused service and server-engine prototypes require proof before removal.
- UI decomposition should follow domain and workflow seams rather than file-size targets alone.
- Notification scheduling architecture should wait for an explicit lifecycle and permission model.

## 20. Architectural roadmap

The roadmap is ordered by dependency and risk, not by feature visibility.

The foundations in Stages 1 to 3 are substantially present. The product order
from Stage 4 onward follows the validated brain contract: understand real
consequences first, then exceptions, optimal scheduling, language breadth,
document intake, and proactive mental-load assistance.

### Stage 1 — Secure and stabilize foundations

- establish protected anonymous-capable identity;
- isolate local data by identity;
- introduce safe account linking and reconciliation;
- protect and validate the AI backend boundary;
- define bounded error and timeout behavior;
- correct cloud synchronization and recurring-series reliability risks;
- add live-path and security regression tests.

### Stage 2 — Extract the typed conversation workflow boundary

- extract a typed Conversation Coordinator or Conversation Engine from `ChatScreen` without changing stable behavior;
- assign active interaction, pending-information, proposal, confirmation, interruption, cancellation, and action lifecycle state to that boundary;
- preserve deterministic domain ownership, persistence rules, backend security, and existing confirmation behavior;
- protect the live conversation and action paths with boundary-focused regression tests.

### Stage 3 — Establish shared context ownership

- define the Life Context contract;
- clarify profile and memory precedence and provenance;
- define memory relevance, correction, deletion, and consolidation policy;
- unify routine projections used by planning and future engines;
- preserve current planning invariants.

### Stage 4 — Model real availability and consequences

- define typed Reasoning Engine inputs from conversation state and Life Context projections;
- make person, relationship, responsibility, commitment and user consequence the shared reasoning units;
- distinguish another person's schedule from the primary user's availability;
- block only a known participation, preparation, transport, waiting, replacement or responsibility consequence;
- represent certainty so probable context cannot become a hard conflict;
- preserve deterministic planning, conflict, persistence and security ownership;
- add general household-shape and non-household-person regression tests.

The Stage 4 availability contract now preserves another person's schedules as
visible context while excluding them from primary-person blockers. A confirmed
responsibility may add either one explicit dated consequence or one explicit
weekly civil-time consequence for the responsible person. Weekly consequences
carry person references, a closed consequence kind, weekdays and local
start/end times; they remain bounded by the responsibility validity period.
Planning blocks only that consequence range when the primary person is the
declared responsible person. No relationship label, school period, work period
or household membership can manufacture transport, waiting or participation.

The first Stage 4 conversation write path is also live. It recognizes a
bounded, explicit first-person recurring responsibility such as regularly
transporting, accompanying, waiting for, caring for or helping a known person.
It resolves that person from HumanModel, asks only for a missing identity or
time range, then requires one explicit confirmation before writing the
canonical responsibility and its weekly consequence. This path runs before
generic Routine detection, prevents exact duplicates, preserves one pending
local write when offline and never infers a responsibility from another
person's schedule or relationship label.

A child's explicit school schedule may now support one bounded clarification
about school drop-off. It is never asked when Chat opens: Zelia waits for a
real dated planning request whose start touches the school-entry transition,
asks whether the primary person generally handles that trip, then resumes the
original request automatically after the answer. The schedule is only the
reason to ask; it is never itself proof of responsibility and never blocks the
primary person's agenda. A yes records a canonical transport responsibility.
When the explicit school travel duration is available, only the short journey
around school entry is protected. Otherwise, the known entry instant becomes
a one-minute technical planning marker so an Event placed exactly at that
confirmed transition cannot pass unnoticed; this marker does not pretend to
know the journey duration. Older confirmed answers are completed silently
from the current schedule without asking again. A no is retained as a rejected
proposal so the question is not repeated. No school duration, pickup
responsibility or travel duration is invented. If this optional clarification
cannot be loaded, the original planning request continues unchanged.

### Stage 5 — Handle cancellations, reports and exceptions

- distinguish one occurrence from an entire recurrence;
- support cancelled, moved, replaced and exceptionally skipped commitments;
- compare importance and flexibility without silently deciding for the user;
- keep corrections reversible and prevent contradictory duplicates.

The first Stage 5 slice introduces an account-owned, revisioned
`RoutineOccurrenceOverride`, stored independently from the recurring Routine.
It identifies one source occurrence by Routine and civil date. `cancelled` and
an entity-linked `replaced` suppress only that occurrence; a labelled
`replaced` projects the exceptional replacement visibly on that date; `moved`
keeps its stable source identity while projecting it at one explicit
replacement date and local time.
Tombstones reverse an override without deleting its audit history. The Routine
Occurrence Engine rejects duplicate overrides and a move onto another
occurrence of the same Routine instead of silently producing contradictory
copies. The first conversation slice understands bounded French cancellation,
move and replacement requests, resolves the exact applicable Routine and civil
date, asks only for missing information, and writes the revisioned override
only after an explicit yes. A refusal, a date without that Routine, an Event
mutation, or a whole-series request produces no occurrence override. The
recurring Routine and its other occurrences are never rewritten.

### Stage 6 — Find the best real slot

- rank available slots using location, travel, preparation, adjacent commitments and useful margin;
- include preferences, rhythm, fatigue, responsibilities, importance and flexibility when evidenced;
- propose the best contextual option instead of the first empty gap;
- keep explanations concise, truthful and human.

### Stage 7 — Broaden natural-language understanding

- support spelling errors, voice-transcription variants, abbreviations, familiar language and bounded slang;
- support several intents in one message and contextual corrections;
- generalize every normalization across values instead of patching one observed phrase;
- maintain zero unauthorized action for negation, contradiction and material ambiguity.

### Stage 8 — Import structured schedules and documents

- read image and PDF schedules, appointments and time-related documents;
- extract person, date, time, place, recurrence and uncertainty into typed proposals;
- provide one global review with targeted line correction;
- persist only validated structured information and discard the original document after processing.

### Stage 9 — Anticipate mental load

- build explainable preparation plans for events, travel, deadlines and life transitions;
- separate urgent alerts, important anticipation and optional daily-summary suggestions;
- limit noise and require personal, actionable evidence for every proactive suggestion;
- formalize Priority, Task, Shopping and Notification lifecycles around this policy.

### Stage 10 — Extend connections and premium capabilities

- add external calendar, mapping, health or service connections only behind explicit scope and ownership contracts;
- preserve local truth, privacy, correction and graceful degradation;
- leave room for future trusted sharing between two ZELIA accounts without implementing it prematurely;
- finish operational observability, measured optimization and grand-public visual harmonization.

Major new engines should not bypass unfinished identity, persistence, or source-of-truth foundations.

## 21. Documentation architecture

Documentation has explicit levels of authority and scope.

| Document | Purpose | Status |
|---|---|---|
| `docs/MASTER_ARCHITECTURE.md` | Mission, global architecture, ownership, principles, decisions, debt, and roadmap | This document |
| `docs/ZELIA_BRAIN_CONTRACT.md` | Authoritative product behavior for the personal second brain, including people, responsibilities, consequences, availability, memory, language, imports, anticipation and action consent | Current approved product contract |
| `AGENTS.md` | Operational repository contract for human and AI contributors | Current |
| `README.md` | Product/repository orientation and local entry points | Current file is generic and should eventually be replaced deliberately |
| Architecture decision records | One durable decision per identity, persistence, security, schema, or ownership change | Planned |
| Planning architecture | Detailed planning lifecycle, contracts, and invariants | Planned; stable enough to create |
| Firebase data and security contract | Data paths, ownership, identity, sync, rules, and backend boundaries | Planned; must track security migration |
| Conversation workflow architecture | Typed interaction states, transitions, interruption, cancellation, confirmation, action lifecycle, and ownership boundaries | Planned next, after foundation stabilization and before Life Context implementation |
| Client/server conversation contract | Request, response, errors, validation, and compatibility | Planned after transport and typed workflow boundaries stabilize |
| Life Context architecture | Authoritative projection inputs, provenance, precedence, consumers, and exclusion of conversational state | Planned after the typed conversation boundary exists |
| Memory architecture | Memory lifecycle, relevance, correction, deletion, consolidation, and provenance | Postponed until policy stabilizes |
| Notification architecture | Permission, scheduling, delivery, cancellation, and identity | Postponed |
| Operations and deployment runbooks | Approved validation, rollout, rollback, secrets, and monitoring | Planned separately from architecture |

Documentation never replaces repository inspection. When documentation and implementation diverge, contributors must identify whether the code is defective, the documentation is stale, or a planned migration is incomplete.

## 22. Repository governance

Repository work must comply with `AGENTS.md`. At the constitutional level:

- inspect the current repository and approved documentation before implementation;
- preserve unrelated work;
- never infer destructive or remote authority;
- never fabricate confirmation;
- never commit, push, deploy, change Firebase state, or alter Git history without explicit approval;
- make the smallest coherent change;
- trace callers and persistence effects;
- include regression protection proportionate to risk;
- review the complete final diff and working-tree state;
- report validation honestly;
- update architecture documentation only when its level of abstraction is affected.

Historical files, generated files, configuration snapshots, and similarly named engines must not be treated as authoritative without verifying their live role.

## 23. Mémoire synchronisée et révisionnée (V1-M.2)

La mémoire suit désormais le même invariant de concurrence que HumanModel :
Firestore est la référence partagée, le local est le dernier état valide et
une file bornée, et le legacy reste une lecture de compatibilité. Politique et
souvenirs ont des révisions monotones, des mutations idempotentes et des
écritures transactionnelles avec révision attendue. Aucun appareil ne peut
écraser silencieusement une révision plus récente.

La politique est synchronisée séparément des souvenirs et revalidée au moment
de chaque envoi. La pause et le consentement santé restent prioritaires sur une
ancienne intention hors ligne. Les conflits sont fermés, persistés localement
et non assimilés à un succès; les retries, reçus, conflits, cache et pagination
sont bornés. L’expiration historise sans suppression physique.

Le bootstrap restaure un nouvel appareil depuis le cloud, conserve les
mutations locales admissibles et invalide toute référence active au changement
de compte. Life Context ne reçoit que les métadonnées bornées de
synchronisation et les souvenirs autorisés par M.1/LC.3. Conversation ne voit
ni file ni conflit, et Planning ne reçoit aucune mémoire libre. Les parcours
visibles de bibliothèque, correction et suppression relèvent de M.3.

## 24. Contrôle visible de la mémoire (V1-M.3)

La bibliothèque mémoire est désormais une capacité produit explicite.
`MemoryLibraryService` orchestre lecture bornée, détail, explication,
correction, confirmation, rejet, report, archivage, tombstones, restauration
d’archives, conflits et suppression globale. Les écrans restent de simples
consommateurs et n’accèdent à aucune persistance.

Toute action persistante conserve l’identifiant, utilise une mutation M.2
idempotente et contrôle la révision attendue. L’historique produit contient au
plus 50 événements sans ancienne copie du contenu. Une suppression remplace le
contenu par un marqueur neutre et ne peut jamais cascader vers Identity,
HumanModel, Event, Task, Routine, profil ou compte.

## 24. Synchronisation révisionnée Task, Shopping et Profile (V1-Y.1)

Y.1 remplace l’autorité historique des listes complètes par trois flux
révisionnés. Une création commence à la révision 1. Toute mise à jour porte un
`expectedRevision` et une `mutationId`, puis la transaction cloud accepte
uniquement N → N+1. Un retry portant la même mutation est idempotent ; la même
mutation avec un autre résultat et toute révision obsolète deviennent des
conflits explicites. Les suppressions Task et Shopping sont des tombstones :
une mutation ancienne ne peut donc pas ressusciter une donnée.

Les états locaux et les journaux sont séparés par compte et domaine. Les clés
`zelia_y1_<domain>_state_v1:<scope>` et
`zelia_y1_<domain>_journal_v1:<scope>` sont versionnées. Le journal conserve au
maximum 200 mutations, 200 reçus et 100 conflits, avec cinq tentatives au
maximum et une sauvegarde précédente relue en cas de corruption. Le bootstrap
charge au plus 100 documents cloud par domaine, adopte les révisions valides et
préserve les mutations locales non synchronisées. Un échec réseau laisse un
état `queued`/`unavailable`; il n’est jamais annoncé comme succès cloud.

V1-S0.3 durcit ce contrat sans ajouter un second moteur de synchronisation.
Pour Task, Shopping et Profile, l’intention est désormais journalisée avant la
projection locale, puis le bootstrap rejoue séquentiellement les mutations
restantes avec leur `mutationId` original. Un crash entre ces deux écritures
laisse donc une intention récupérable ; la projection locale est reconstruite
depuis le payload fermé du journal avant le retry. Les appels cloud sont bornés
à quinze secondes et les cinq tentatives suivent un backoff exponentiel borné
à cinq minutes. Une réponse arrivée après changement de compte n’acquitte
ni la projection locale ni le journal de l’ancien compte ; le retry idempotent
reprend uniquement lorsque ce compte redevient actif. Une mutation en conflit
reste bloquée par son conflit explicite et n’est pas rejouée en boucle. Les
reçus conservent les 200 identités les plus récentes.

Event conserve son journal spécialisé, ses tombstones, ses cinq tentatives et
ses conflits : S0.3 borne les mutations directes et chaque exécution du worker
cloud à quinze secondes, un timeout journalisé restant une opération durable
en échec réessayable. Memory conserve
sa file, son backoff exponentiel et sa politique propre ; l’état métier et la
mutation sont maintenant écrits ensemble, le bootstrap reprend les mutations
persistées, et les appels cloud sont également bornés. Routine/proposition
reste une transaction idempotente par identifiants stables. HumanModel conserve
son unique pending canonique révisionné. Ces domaines ne sont pas artificiellement
convertis au protocole Y.1.

Les façades `TaskService`, `ShoppingService` et `StorageService` restent
compatibles avec les écrans historiques, mais leurs écritures authentifiées
passent par `TaskRevisionSyncService`, `ShoppingRevisionSyncService` ou
`ProfileRevisionSyncService`. Les anciens documents restent lisibles et sont
convertis additivement lors de leur prochaine mutation. Les réécritures
complètes et suppressions physiques cloud sont refusées.

### Propriété Profile et HumanModel

HumanModel reste seul propriétaire des personnes, relations, foyers,
domiciles, appartenances et responsabilités. `ProfileFieldOwnership` ferme la
liste des champs encore propriétaires de Profile : réglages de planning,
travail, organisation, notifications, langue et préférences générales. Un
patch contenant un champ humain produit
`canonicalOwnershipConflict`; il n’est jamais fusionné. Les extensions legacy
inconnues restent conservées pour compatibilité, mais la payload Profile
révisionnée n’exporte ni personne ni famille.

### Conflits, A.1 et Life Context

Les conflits sont bornés et typés (`revisionConflict`,
`completionConflict`, `listConflict`, `profileFieldConflict`,
`canonicalOwnershipConflict`, corruption ou mauvais compte). Aucun texte libre
n’est fusionné automatiquement. Un retry issu de Conversation conserve
uniquement sa référence A.1 minimale et doit repasser par un
`RevisionedActionRetryGuard`; Pause ou une confirmation Suggestions devenue
obsolète bloque le retry.

Life Context continue de consommer le dernier état métier valide par les
façades account-scoped. Il ne reçoit jamais le journal, les reçus, les
tombstones, les mutations ou les conflits complets. LC.3 reste responsable de
la sélection et des budgets.

Les règles Firestore locales ferment Task, Shopping et Profile : propriétaire
authentifié, scope et identifiant cohérents, version 1, création à la révision
1, incrément exact, `lastMutationId` renouvelé, timestamps serveur, tombstone
monotone et suppression directe interdite. Elles ne sont pas déployées par
Y.1.

Y.2 reste nécessaire pour Routine et Documents. Y.3/Y.4 restent nécessaires
pour les protocoles d’export et la convergence multiappareil plus générale.
Y.1 fournit à A.2 les références techniques stables et reçus d’idempotence
nécessaires, sans confondre journal de synchronisation et ledger d’audit.

## 25. Ledger d’actions et undo réversible (V1-A.2)

Le ledger A.2 est un historique d’audit borné des mutations. Il ne remplace
aucune source de vérité métier et ne duplique aucun journal de synchronisation.
Une entrée relie un type d’action, une décision A.1, un `mutationId`, une
référence métier minimale, la révision attendue et le résultat réel. Aucun
message, prompt, contexte, document source ou modèle métier complet n’y est
conservé.

Le cycle fermé est : proposition ou autorisation, dispatch, puis résultat
`completed`, `pendingSync`, conflit, résultat inconnu ou échec. Un succès ne
peut être enregistré qu’après le résultat du service métier. Le même
`mutationId` désigne une seule entrée logique ; une réutilisation divergente
est refusée. Les écritures cloud suivent une révision propre au ledger et les
écritures locales account-scoped conservent une sauvegarde précédente.

Le stockage local conserve au plus 100 entrées actives et 400 entrées
historiques dans 1 Mio, avec pages de 50 maximum. Le chemin cloud privé est
`users/{uid}/actionLedger/{ledgerEntryId}`. Les règles imposent le propriétaire,
une création en révision 1, N → N+1, une transition autorisée, l’identité
immuable de l’action et l’interdiction de suppression physique.

### Undo

Un undo est une nouvelle action et possède son propre `mutationId` et une
nouvelle entrée liée à l’entrée initiale. `ActionUndoEngine` vérifie de façon
pure le compte, A.1 courant, la policy du domaine, la confirmation, la date
limite et surtout l’égalité entre révision courante et révision résultante.
Une divergence produit `targetChanged`, jamais un overwrite.

Les stratégies Task, Shopping, Event, Profile et Memory ne peuvent être
activées que lorsqu’un adaptateur révisionné fournit un inverse minimal et
borné. `clearList`, `deleteAllMemory`, Identity et Routine restent
explicitement non annulables automatiquement. HumanModel reste auditable mais
nécessite une résolution manuelle tant que son service ne fournit pas un
inverse fermé. MemoryPolicy et le consentement santé restent prioritaires.

Pour Event, seule la création possède aujourd’hui un inverse démontré sûr :
une nouvelle mutation de suppression révisionnée, si l’Event n’a pas changé.
Les updates, changements de participant, règles de récurrence et suppressions
restent audités mais `notUndoable` tant qu’aucun patch inverse fermé ne capture
exactement l’ancien état nécessaire. L’application ne reconstruit jamais un
Event complet depuis le ledger, ne supprime aucune Identity et ne restaure
aucune série ou occurrence par supposition.

Les écritures conversationnelles historiques de
`MemoryLifecycleRepository` sont enveloppées par
`LedgeredMemoryLifecycleRepository`. La proposition, la confirmation,
l’activation et le rejet créent l’entrée avant le dispatch, réutilisent
l’idempotencyKey M.3 comme `mutationId`, puis enregistrent uniquement le
résultat réel. `MemoryLibraryService` reste la façade des corrections,
archives, restaurations et tombstones ; `MemorySyncService` reste propriétaire
de son journal, y compris des expirations déterministes désormais observées
comme `pendingSync`. Cette observation ne duplique ni MemoryPolicy ni le
protocole M.2/M.3.

Le mode Suggestions exige une confirmation fraîche pour la mutation inverse ;
le mode Pause autorise la consultation mais bloque l’undo et toute reprise.
Hors ligne, un undo ne peut être annoncé comme terminé : il reste
`undoPendingSync` uniquement si le domaine accepte la mutation révisionnée.

### Réconciliation et interface

Le bootstrap rapproche les versions locales et cloud par identifiant et
`mutationId`. Une entrée incomplète ne constitue jamais une autorisation de
rejouer l’action métier. Les résultats inconnus doivent être rapprochés avec
les reçus du domaine ; aucun replay général ou destructif n’existe.

L’écran « Historique des actions » affiche une projection française bornée :
domaine, origine, date, état et disponibilité de l’annulation. Les identifiants,
révisions, patches et codes internes ne sont jamais affichés. A.3 reste
responsable d’une éventuelle harmonisation générale des confirmations. Routine
et Documents restent reportés à Y.2.

Le bouton « Annuler » n’est rendu que pour une entrée `undoAvailable`. Une
opération irréversible ou sans inverse sûr affiche une explication simple et
ne peut pas atteindre `ActionUndoCoordinator`. Une capacité conditionnelle
redevient indisponible dès que la révision, A.1, MemoryPolicy, la santé ou le
tombstone ne correspondent plus.

La suppression globale est renforcée, paginée par lots de 20, reprenable et
isolée au compte authentifié. Hors ligne, elle demeure pending. Les mémoires
legacy Routine et les références structurées sont archivées pour préserver la
continuité des domaines propriétaires.

Les tombstones sont filtrés à la frontière Life Context, les archives ne sont
pas actives, Conversation reconstruit une projection bornée et Planning ne
reçoit toujours aucune mémoire libre. Les conflits restent explicites sans
merge automatique ni exposition de révision.

## 26. Confirmations d’actions canoniques — V1-A.3

`ActionConfirmation` est l’unique contrat exécutable de confirmation. Il lie
une action structurée à un compte interne, une génération de session, un
`ActionPending`, une éventuelle entrée du ledger A.2, un `mutationId`, une
portée fermée et une expiration obligatoire. Son empreinte est calculée de
façon déterministe depuis le type, le domaine, la cible, l’opération, la
révision attendue, le risque et les champs typés normalisés. Le texte affiché,
la locale et les timestamps sans portée métier n’entrent jamais dans cette
empreinte.

`ActionConfirmationCoordinator` agrège les exigences A.1, métier, sensible,
destructive, Memory/santé, Identity et conflit. Deux exigences ne partagent une
confirmation que si elles visent exactement la même empreinte et une portée
compatible. Une décision distincte — par exemple créer ou lier une Identity
pendant une opération Event — conserve une confirmation distincte. Les actions
tierces restent fermées et non exécutables.

Le cycle fermé est : proposition, attente, réponse typée, acceptation,
revalidation, consommation unique, dispatch, puis résultat métier réel. Une
acceptation ne vaut jamais succès. Les réponses dupliquées sont idempotentes,
les réponses divergentes sont refusées et une confirmation expirée, consommée,
supplantée, issue d’un autre compte ou d’une autre session ne peut pas être
réutilisée. Une modification du payload, une nouvelle alternative Smart
Planning ou un conflit produit une nouvelle empreinte et une nouvelle
confirmation.

Les durées sont centralisées : cinq minutes pour les actions destructives et
les conflits, dix minutes pour une réservation Smart Planning, quinze minutes
pour une mutation simple. L’horloge est injectable. Le mode Suggestions ajoute
une exigence fusionnable ; Pause bloque immédiatement toute confirmation
exécutable et le retour à un mode actif n’exécute rien rétroactivement. A.1,
C.3, les policies de domaine, la révision et le conflit sont relus avant le
dispatch.

Event, Smart Planning, Task et Shopping utilisent le contrat commun dans les
parcours conversationnels. Smart Planning empreinte le créneau exact avec date,
heure, durée, trajets aller/retour, marge, participant et récurrence. Routine
peut adopter le même contrat pour ses mutations déjà supportées, mais A.3
n’ajoute ni synchronisation Y.2 ni undo Routine. Memory, HumanModel et Identity
conservent leurs protections propres ; leur présentation n’est fusionnée que
pour une décision strictement identique.

Le backend peut proposer `actionProposal` ou `confirmationRequired`, mais il
ne peut fabriquer ni acceptation, ni identifiant, ni empreinte, ni token de
confirmation, ni résultat métier. Flutter crée et détient la confirmation
réelle. Le composant commun affiche uniquement une présentation française
bornée et retourne un choix typé ; il ne charge aucune policy et n’appelle
aucun service métier. Hors ligne, seul le résultat réel du domaine peut devenir
`pendingSync`; aucun succès cloud n’est annoncé.

Les diagnostics ne contiennent ni présentation, ni payload, ni empreinte
complète, ni donnée personnelle. Les intégrations tierces et Y.2 restent hors
périmètre.

## 27. Notifications locales privées — V1-N.1

V1-N.1 fournit une infrastructure locale iOS/Android ; elle ne détecte aucun
oubli, retard, conflit ou échéance et ne produit aucun résumé quotidien. N.2
reste propriétaire des futurs détecteurs et N.3 des résumés et alertes
avancées. Aucun FCM, push distant, connecteur ou serveur de notification n’est
introduit.

`NotificationPermissionService` sépare la lecture silencieuse de l’état et la
demande explicite. L’initialisation du plugin désactive les demandes iOS
automatiques ; Android ne demande jamais la permission depuis `MainActivity`.
Le réglage `NotificationSettings` est versionné, local et isolé par compte. En
l’absence de valeur valide il désactive les notifications, conserve le mode
`genericOnly` et n’active ni son, ni vibration, ni badge. La synchronisation
multiappareil de ce réglage reste hors périmètre.

`LocalNotificationRequest` porte une catégorie locale fermée (`test`,
`explicitReminder`, `pendingActionAttention`, `systemInformation`), une
identité logique, un instant ou horaire local explicite, un fuseau IANA, une
expiration éventuelle et une destination sûre. N.2 active uniquement
`forgottenItemDetection`, `conflictDetection`, `delayDetection` et
`deadlineDetection`; les catégories N.3 restent refusées. Le registre
SharedPreferences est account-scoped,
validé à la relecture, sauvegardé avant remplacement et borné à 128 entrées.
Les identifiants plateforme sont déterministes ; les collisions sont refusées.

`LocalNotificationScheduler` est l’unique frontière de programmation,
reprogrammation, remplacement, annulation, notification de test et
réconciliation plateforme. Une même demande est idempotente, une demande
divergente portant le même identifiant est refusée et une même
`replacementKey` remplace explicitement l’ancienne programmation. Aucun succès
n’est annoncé avant le retour de l’API locale. Android utilise des alarmes
inexactes et trois canaux versionnés ; aucune permission d’alarme exacte ni
action système mutable n’est déclarée. Les notifications programmées sont
restaurables après redémarrage.

Les horaires absolus conservent leur instant. Les horaires muraux sont résolus
dans leur fuseau IANA ; une heure inexistante au passage à l’heure d’été est
refusée et une heure ambiguë est résolue de manière déterministe. Un changement
de fuseau nécessite une réconciliation/reprogrammation explicite : aucune
interprétation serveur implicite n’existe.

`NotificationPrivacySanitizer` est la seule fabrique de contenu système. Le
titre est « Zélia » et le corps reste générique ou caché. Le payload contient
seulement une version, un identifiant opaque, une destination fermée et un
jeton local opaque. Il n’embarque ni UID, scope, entité, ledger, confirmation,
texte métier ou donnée personnelle. La visibilité Android est privée ou
secrète ; iOS utilise la même présentation générique.

`NotificationInteractionCoordinator` valide le payload, le compte courant,
l’expiration, le registre et le jeton, puis retourne uniquement une intention
de navigation. Un clic, y compris après lancement à froid, ne confirme pas
A.3, ne consomme pas une confirmation, n’effectue aucun undo et n’écrit aucun
domaine. Un changement de compte annule les programmations de l’ancien compte
et invalide les jetons actifs. A.1 est relu par le parcours chargé après
navigation ; Pause ne désactive pas arbitrairement toutes les notifications
système.

L’écran de réglages dépend d’un contrôleur injecté : il affiche l’état,
explique le contenu générique, déclenche la permission uniquement sur clic,
enregistre les options et fournit un test local non répétitif. Il n’accède ni
au plugin ni au stockage. Les diagnostics restent limités aux catégories,
états, codes et compteurs techniques et n’incluent jamais titre, corps, payload,
jeton, destination exacte, UID ou contenu métier.

## 28. Détections proactives déterministes — V1-N.2

V1-N.2 ajoute quatre détecteurs purs : échéance explicite, retard
objectivement vérifiable, conflit confirmé par la frontière Planning canonique
et oubli potentiel fondé sur une dépendance R.2 confirmée ou un rappel
explicite. Aucun détecteur n’analyse un titre, une mémoire libre ou une absence
de donnée ; aucun n’appelle OpenAI. Une Task sans horaire ne devient pas en
retard et une Task ordinaire ne devient pas un oubli.

`DetectionEvidence` représente une preuve structurée, sa révision, sa
fraîcheur et sa disponibilité. `DetectionCoverageState` distingue `complete`,
`partial`, `stale`, `unavailable`, `unsupported` et `corrupted`. Une passe
partielle signifie seulement qu’aucun signal éligible n’a été trouvé dans les
données évaluables : elle ne prouve jamais l’absence globale d’un problème.
L’adaptateur N.2 consomme les sections canoniques Life Context et les
dépendances explicites LC.2/R.2 sans lire de repository et sans reconstruire
de relation.

`ProactiveDetectionPolicy` centralise les horizons, périodes de grâce,
cooldowns, bornes par domaine, limites par passe et durée de validité. Ces
valeurs sont des protections techniques, pas des réglages produit N.3. Les
résultats Priority R.1–R.3 peuvent ordonner des signaux déjà valides ; ils ne
créent aucune preuve et ne rendent jamais un signal insuffisant éligible.

`ProactiveDetectionEngine` est l’unique agrégateur. La priorité de collision
est conflit, échéance passée, retard, échéance approchante puis oubli
potentiel. L’empreinte d’incident est technique et déterministe ; une seule
notification est conservée, les raisons secondaires sont bornées, et les
signaux résolus restent brièvement disponibles pour le cooldown. Le registre
local versionné est isolé par compte, sauvegardé avant remplacement, limité à
128 entrées et ne conserve aucun contenu personnel.

`DetectionNotificationCoordinator` est la seule jonction avec N.1. Il
programme, remplace ou annule selon le résultat réel du scheduler, avec un
contenu générique et un payload minimal. Le cycle de vie est événementiel et
borné (bootstrap authentifié, premier plan, changement Event/Task/Routine ou
dépendance, fuseau, reconnexion, résolution) ; il n’existe ni boucle active,
ni worker permanent. Hors ligne, seules les preuves locales courantes restent
évaluables ; stale ne devient jamais current.

Un clic reste une navigation N.1 sûre : aucune Task n’est terminée, aucun
Event déplacé, aucune confirmation A.3 consommée et aucune mutation A.2
créée. Les modes A.1 n’autorisent aucune action automatique. N.3 reste
propriétaire des fréquences configurables, résumés quotidiens, alertes
critiques et réglages avancés.

## 29. Politique produit des notifications — V1-N.3

`ProactiveNotificationPolicy` est l’unique policy produit de diffusion. Elle
est versionnée, locale, isolée par compte et relue après chaque écriture. Son
défaut est restrictif : alertes automatiques, résumé quotidien et alertes
importantes sont désactivés. La corruption ou une version future revient à ce
défaut sûr. Aucune synchronisation cloud de ces réglages n’est introduite.

Chaque catégorie possède un mode fermé (`immediate`,
`dailySummaryOnly`, `immediateAndSummary`, `disabled`), un cooldown, une
limite quotidienne, une priorité et des niveaux minimums de confiance et de
preuve. Ces réglages filtrent seulement les signaux valides de N.2 : ils ne
créent jamais de preuve, d’échéance, de retard, de conflit ou d’oubli. Priority
R.1–R.3 peut départager des signaux déjà éligibles mais ne relève ni leur
confiance ni leur importance.

La pause N.3 est explicite, temporaire ou indéfinie. Elle suspend uniquement
les catégories proactives sélectionnées et ne modifie jamais A.1. Les rappels
explicitement demandés restent distincts. La reprise déclenche au plus une
nouvelle évaluation événementielle bornée ; aucune notification rétroactive ni
rafale n’est produite. Les heures calmes sont définies en minutes locales,
jours et fuseau IANA, peuvent traverser minuit, et appliquent un seul report,
un prochain résumé ou une suppression prudente selon la policy.

`NotificationRateLimitPolicy` borne les diffusions quotidiennes, par fenêtre
et par catégorie, l’espacement, les reports, remplacements, actifs et éléments
du résumé. L’historique technique local est account-scoped, sauvegardé avant
remplacement, limité à 128 décisions et purgé après trente jours. Il ne
contient aucun contenu métier.

Une « alerte importante » est une qualification produit, jamais une alerte
système critique. Elle exige un signal N.2 actuel, non ambigu, de preuve forte,
avec sévérité structurée et catégorie admissible. `potentialOmission` n’est
pas admissible par défaut. Ces alertes ne contournent ni permission,
désactivation, pause indéfinie, mode silencieux ou réglages du téléphone.
Aucun entitlement Apple Critical Alerts, alarme exacte Android, full-screen
intent, canal médical ou permission supplémentaire n’est ajouté.

`DailySummaryBuilder` produit une projection déterministe et bornée de
références techniques, catégories, révisions et couverture. Il exclut les
signaux résolus, expirés, désactivés ou insuffisants et retourne `noSummary`
quand rien d’utile n’est disponible. Il n’analyse aucun texte et n’appelle
aucun LLM. Une seule programmation est conservée par date logique grâce à une
identité et une `replacementKey` stables ; désactivation ou résumé vide
annulent la programmation future. Un changement de fuseau reconstruit
explicitement l’instant local, y compris autour des changements d’heure.

`ProactiveNotificationPolicyEngine` est pur et décide `schedule`,
`includeInDailySummary`, `deferUntil` ou une suppression fermée. Le chemin de
production est N.2 → `ProactiveNotificationOrchestrator` → scheduler N.1.
L’orchestrateur charge Auth, la policy, les permissions et les registres,
applique les décisions, puis enregistre uniquement les résultats réels. Il
n’appelle aucun domaine métier, ne crée aucun ledger et n’exécute aucune
action. Les signaux non diffusés restent dans le registre N.2.

Le résumé système reste « Zélia — Ton résumé quotidien est disponible dans
l’application. » Les autres notifications restent également génériques. Le
clic passe par le coordinateur N.1, vérifie compte, expiration et jeton opaque,
puis ouvre une vue interne en lecture seule. Toute action ultérieure repasse
par A.1–A.3 et A.2 ; la notification elle-même ne confirme et ne mute rien.

L’écran Notifications utilise des contrôleurs injectés pour l’activation
générale, les catégories, la pause, les heures calmes, la fréquence, le résumé
et les alertes importantes. Il n’accède ni au plugin ni à
SharedPreferences. La vue du résumé affiche des comptes et formulations
prudentes, recharge les signaux et ne devient jamais une source métier.

N.1 reste l’unique scheduler et propriétaire de la confidentialité plateforme.
N.2 reste l’unique moteur de détection. N.3 n’ajoute ni worker, polling, FCM,
push distant, marketing, voix, intégration externe ou réglage synchronisé.

## 29. Change policy for this document

Change this document when:

- ZELIA's mission or product philosophy changes;
- an architectural layer is added, removed, or materially redefined;
- source-of-truth ownership changes;
- an engine becomes an accepted architectural capability;
- identity, security, persistence, or confirmation policy changes;
- a planned architecture becomes current state;
- technical debt becomes invalid, resolved, or constitutionally significant;
- the roadmap changes because dependencies or product direction changed.

Do not change this document solely because:

- a class or file is renamed;
- an internal helper is extracted;
- a dependency receives a routine update;
- UI styling changes;
- a narrow bug is fixed without changing an invariant;
- an experimental implementation exists without approved architectural status.

Every change must be based on the verified repository and must preserve the distinction between current state and planned architecture.

## 29. Definition of architectural readiness

A ZELIA capability is architecturally ready when:

- its mission and boundaries are explicit;
- its authoritative inputs and outputs are known;
- interaction state is separated from domain truth and shared context projections;
- its relationship to identity and persistence is defined;
- its interactions with other engines do not duplicate ownership;
- consequential operations have confirmation semantics;
- failure behavior is bounded and truthful;
- backward compatibility is understood;
- critical behavior is protected by tests at the appropriate layers;
- security and privacy implications are reviewed;
- rollout and rollback can be described without inventing missing infrastructure.

Code existing in the repository does not by itself make an engine architecturally ready. Conversely, a planned engine should not be implemented as a broad new subsystem until its prerequisites and ownership are clear.

## 30. Enduring direction

ZELIA should grow by deepening trust, context, and deterministic coordination—not by accumulating disconnected “smart” features.

Its durable product objective is a distinct second brain for each user: one
that understands people and commitments through their real consequences,
learns progressively without intrusion, and reduces mental load with the least
possible input.

The durable architecture is one in which:

- the user can begin immediately and remain in control;
- identity protects data without creating unnecessary friction;
- context is relevant, correctable, and private;
- engines have clear ownership and explicit interactions;
- AI improves understanding and explanation without owning truth;
- planning respects the full reality of time;
- actions occur only with adequate information and authority;
- persistence and feedback are honest;
- new capabilities extend stable contracts instead of bypassing them.

That direction is the standard against which future architecture, engines, product features, and repository decisions must be evaluated.
