# ZELIA Master Architecture

## Document status

This document is the constitutional architectural reference for ZELIA. It defines the durable mission, boundaries, principles, ownership model, system relationships, decision framework, and long-term direction of the repository.

It is intentionally not an implementation manual. Individual classes, APIs, schemas, storage layouts, operational commands, and migration procedures belong in narrower documents and in the code itself.

Statements labeled **Current state** describe behavior verified in the repository when this document was created. Statements labeled **Planned architecture** describe an approved direction that is not yet fully implemented. Repository-specific facts must always be rechecked before configuration, security, persistence, or remote work.

This document must evolve deliberately. It should change when ZELIA's mission, system boundaries, architectural ownership, safety model, or long-term direction changes—not whenever a service is renamed or refactored.

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

**Current state:** `ChatScreen` coordinates message state, pending information and actions, planning proposals, confirmations, backend requests, validation, persistence calls, interruption paths, and user feedback. There is no standalone typed Conversation Engine.

**First extraction target:** A typed Conversation Coordinator or Conversation Engine will be extracted from `ChatScreen` without changing stable user behavior. It will own active interaction state, pending information, proposals, selection and confirmation state, interruption, cancellation, and the action lifecycle.

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
The current production conversation and planning workflows retain their
legacy paths until their dedicated migrations; LC.3 adds no second
multi-domain reader and does not silently send an additional context to
OpenAI. Priority, final conversation orchestration, and planning decisions
remain separate later phases.

### 7.3 Profile Engine

**Current state:** Profile models, persistence, structured context building, and planning reasoning exist, but responsibilities remain distributed between application state, a large profile screen, and services.

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

**Current state:** Profile schedules and recurring memories can produce blocked planning periods. Weekly, weekday, biweekly, and other recurrence-date matching capabilities exist in the planning domain.

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

**Current state:** Rule-based priority, time urgency, task scoring, ordering, and suggestions exist and are consumed by home and task screens. The public product contract for scores and thresholds is not yet fully documented or tested.

**Planned architecture:** Priority combines explicit importance, deadlines, domain impact, time sensitivity, and life context through explainable deterministic rules. It ranks work; it does not silently execute or reschedule it.

### 7.8 Reasoning Engine

**Current state:** Reasoning is distributed across profile reasoning, memory reasoning, planning services, prompt context, and model selection. There is no single verified general-purpose Reasoning Engine.

**Planned architecture:** The Reasoning Engine consumes typed conversation state and typed Life Context projections to support multi-domain organization. It must not replace deterministic domain engines or the domain owners of conflict, persistence, confirmation, or security.

### 7.9 Task Engine

**Current state:** Tasks have a model, local/cloud persistence, conversational creation, priority processing, and dedicated UI.

**Planned architecture:** The Task Engine owns task lifecycle, state transitions, scheduling intent, priority projections, and stable persistence semantics. A task is not a calendar reservation until planning and confirmation convert it into one.

### 7.10 Shopping Engine

**Current state:** Shopping items have a model, local/cloud persistence, conversational creation, grouping metadata, and dedicated UI.

**Planned architecture:** The Shopping Engine owns shopping-item lifecycle, normalization, grouping, and future context-aware assistance. It remains distinct from general tasks even when both originate in one message.

### 7.11 Notification Engine

**Current state:** Local notification capability exists and is invoked after selected operations. A complete scheduling, cancellation, permission, recurrence, and identity lifecycle is not yet established.

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

### 9.1 Current state

The Flutter chat experience, primarily through `ChatScreen`, coordinates message state, pending information and actions, planning paths and proposals, backend requests, validation, confirmation, persistence calls, interruption and cancellation paths, and feedback. The backend receives profile, memory, reasoning, and event context, then returns a strict reply/actions/memories object. Client validation remains mandatory before action handling.

The active remote AI boundary is the single Firebase callable
`chatWithZeliaCallable`. It requires a Firebase Auth UID, including an anonymous
UID, and derives identity only from verified callable context. The historical
HTTP transport is no longer exported or present in the Flutter client.
Production and staging enforce App Check. Debug uses the official debug
providers. The explicit emulator environment connects Auth, Firestore and
Functions to localhost and is the only server environment that omits App Check.

Before OpenAI execution, a transaction consumes a technical quota from one
deny-by-default Firestore document per UID. It stores no conversation content.
Its bounded settings are `ZELIA_AI_CHAT_QUOTA_LIMIT` and
`ZELIA_AI_CHAT_QUOTA_WINDOW_SECONDS`; it is not a commercial entitlement model.

### 9.2 Planned architecture

The first architectural extraction after foundation stabilization is a typed Conversation Engine that preserves the current user-visible workflow while moving active interaction state and transitions out of `ChatScreen`. It owns pending information, proposals, selection, confirmation, interruption, cancellation, and action lifecycle state. Domain engines continue to own truth and rules; repositories own persistence; the backend owns its security boundary; and Life Context owns contextual facts rather than conversational state.

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

### Planned architecture

The AI boundary uses Firebase Authentication, anonymous authentication for
immediate use, callable Functions, production App Check, strict request
validation, a transactional server quota, bounded errors and timeouts, and no
unrestricted fallback endpoint.

Firebase project, database, region, provider, enforcement, secret, and deployment changes always require explicit approval and current-state verification.

### Diagnostic and error policy

**Current state:** Flutter and Functions use one minimal diagnostic boundary per
runtime. Production, staging, debug and emulator are explicit environments, but
none of them may log user content. Diagnostics are deny-by-default: they accept
only a bounded technical component, step, stable code, severity/environment,
random correlation ID and explicitly allowlisted scalar metrics. Arbitrary
objects, exceptions and stack traces are never serialized.

Conversation text, prompts, model responses, memories, profiles, events, tasks,
shopping data, documents, names, contact details, addresses, birth dates,
health data, Firebase UIDs, Auth/App Check tokens, credentials, secrets, request
bodies and Firestore documents are forbidden in logs in every environment.
Debug and emulator may provide additional technical scalar metadata only; they
do not relax the content policy. Test fixtures must remain synthetic.

The shared error taxonomy keeps Firebase-compatible stable codes where useful
and maps authentication, App Check, permissions, validation, quota, network,
timeout, availability, conflict/stale revision, absence, cancellation, storage,
synchronization and unknown failures to non-sensitive French messages and a
retry policy. Correlation IDs are random and never derived from an account or
business object. No analytics, crash-reporting provider or remote observability
platform is introduced by this policy.

Remaining limitation: diagnostics currently use local/runtime logging sinks.
Retention, operational dashboards, crash reporting, support workflows and
organization-wide historical log remediation require separate approved work.

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
network and microphone access; gallery selection uses the modern system picker
and does not request broad storage, camera, location, contacts, or notification
permissions. iOS declares microphone, speech-recognition, and photo-library
usage because those paths are reachable today. Distribution signing and
physical-device release validation remain deferred; local release validation
does not require a paid Apple Developer membership.

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
- Local persistence is not identity-scoped, and account transitions lack a complete reconciliation policy.
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

### Stage 4 — Formalize cross-domain reasoning

- define typed Reasoning Engine inputs from conversation state and Life Context projections;
- preserve deterministic planning, conflict, persistence, confirmation, and security ownership;
- add explainable, bounded multi-domain reasoning contracts and regression tests.

### Stage 5 — Mature core domain engines

- formalize Priority Engine behavior;
- formalize Task and Shopping lifecycle contracts;
- mature Routine and Profile engine boundaries according to Life Context dependencies;
- establish the Notification Engine lifecycle;

### Stage 6 — Expand product intelligence

- multi-domain organization and scenario reasoning;
- proactive but user-controlled suggestions;
- richer routine and life-context assistance;
- broader platform and notification capabilities;
- operational observability and measured optimization.

Major new engines should not bypass unfinished identity, persistence, or source-of-truth foundations.

## 21. Documentation architecture

Documentation has explicit levels of authority and scope.

| Document | Purpose | Status |
|---|---|---|
| `docs/MASTER_ARCHITECTURE.md` | Mission, global architecture, ownership, principles, decisions, debt, and roadmap | This document |
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

La suppression globale est renforcée, paginée par lots de 20, reprenable et
isolée au compte authentifié. Hors ligne, elle demeure pending. Les mémoires
legacy Routine et les références structurées sont archivées pour préserver la
continuité des domaines propriétaires.

Les tombstones sont filtrés à la frontière Life Context, les archives ne sont
pas actives, Conversation reconstruit une projection bornée et Planning ne
reçoit toujours aucune mémoire libre. Les conflits restent explicites sans
merge automatique ni exposition de révision.

## 25. Change policy for this document

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

## 26. Definition of architectural readiness

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

## 27. Enduring direction

ZELIA should grow by deepening trust, context, and deterministic coordination—not by accumulating disconnected “smart” features.

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
