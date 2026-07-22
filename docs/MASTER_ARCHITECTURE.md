# ZELIA Master Architecture

## Document status

This document is the constitutional architectural reference for ZELIA. It defines the durable mission, boundaries, principles, ownership model, system relationships, decision framework, and long-term direction of the repository.

It is intentionally not an implementation manual. Individual classes, APIs, schemas, storage layouts, operational commands, and migration procedures belong in narrower documents and in the code itself.

Statements labeled **Current state** describe behavior verified in the repository when this document was created. Statements labeled **Planned architecture** describe an approved direction that is not yet fully implemented. Repository-specific facts must always be rechecked before configuration, security, persistence, or remote work.

This document must evolve deliberately. It should change when ZELIA's mission, system boundaries, architectural ownership, safety model, or long-term direction changes—not whenever a service is renamed or refactored.

### Conversational event mutation foundation

**Current state:** Phase 4I-A defines a closed `event_mutation` backend action
containing only an `update` intent, structured target criteria, and requested
changes. It never carries an event ID. The server removes malformed or
ungrounded mutations; Flutter validates again and deterministically selects
current events by normalized title, exact date, exact time, and normalized
category.

Zero matches do not create an event. One stable-ID match creates a typed
confirmation. Multiple matches create a bounded, expiring clarification whose
numbered choice is resolved locally without an LLM. Final confirmation reloads
the event and compares it with its immutable snapshot; disappearance,
concurrent modification, or a protected-range conflict blocks the write.

Only title, date, time, duration, outbound/return travel, margin, notes, and
category can change. Recurrence, deletion, duplication, participants, Identity,
and bulk updates remain excluded. Backend context contains no event ID, notes,
account scope, Firestore metadata, participant link, or Identity data. Calendar
growth will require a separate bounded context-window policy; this phase does
not introduce unbounded semantic matching.

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

**Planned architecture:** ZELIA remains immediately usable without forcing the user to create a visible permanent account. A temporary Firebase identity should protect backend and user-owned data, while a later account upgrade preserves or safely reconciles that identity and data.

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

**Planned architecture.** The Life Context Engine will provide a bounded, typed view of the user's relevant reality. It will reconcile profile data, durable memory, current instructions, time context, routines, and known constraints while preserving provenance and precedence.

It must not become a second database or silently invent facts. Planning, priority, reasoning, and notification capabilities should consume its projections rather than independently interpreting the same raw context.

Life Context remains the first shared authoritative context projection. Its implementation follows extraction of the typed conversation workflow boundary; it does not own conversational state.

### 7.3 Profile Engine

**Current state:** Profile models, persistence, structured context building, and planning reasoning exist, but responsibilities remain distributed between application state, a large profile screen, and services.

**Planned architecture:** The Profile Engine owns stable user-provided context, validation, correction, and domain projections. It does not own inferred conversational memory.

### 7.4 Memory Engine

**Current state:** Eligibility, categorization, normalization, exact duplicate prevention, persistence, context construction, reasoning, similarity helpers, consolidation helpers, and recurring-memory schedule interpretation exist. Not every helper is active in the live pipeline. Memory modification and deletion are not yet complete product flows.

**Planned architecture:** The Memory Engine owns the lifecycle of durable learned context: extraction eligibility, provenance, persistence result, retrieval relevance, correction, deletion, consolidation, and projections into other engines. It must preserve creation metadata when that metadata anchors recurrence.

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

The existing remote AI boundary is a public HTTP Function. Authentication is optional in the current application. These are current-state facts and known security debt, not the desired final architecture.

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
- One-off actions do not become memory merely because they contain important words.
- Memory persistence must be successful before success is claimed.
- Exact and semantic duplicate policies must remain distinguishable.
- Memory context is bounded and selected through an explicit relevance policy.
- Stored creation metadata is preserved when recurrence depends on it.
- Memory reasoning may produce planning constraints only from complete and applicable evidence.
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

Firestore data is UID-owned and deny-by-default outside the user subtree. Storage is deny-all. The OpenAI secret is held by the Functions environment. The public HTTP AI endpoint does not yet implement the planned identity and application-attestation boundary.

### Planned architecture

The AI boundary uses Firebase Authentication, anonymous authentication for immediate use, callable Functions, App Check after monitored rollout, strict request validation, bounded errors and timeouts, and no unrestricted fallback endpoint.

Firebase project, database, region, provider, enforcement, secret, and deployment changes always require explicit approval and current-state verification.

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
| ZELIA remains usable without visible account registration | Planned architecture | Immediate usefulness is a product requirement |
| Anonymous Firebase identity protects nonregistered sessions | Planned architecture | Enables UID ownership without forced registration |
| The AI boundary migrates to protected Firebase-native callable access | Planned architecture | Auth, App Check, and validation address different abuse risks |
| App Check enforcement follows client rollout and monitoring | Planned architecture | Immediate enforcement could lock out legitimate clients |
| A typed Conversation Engine is extracted before new shared engines | Planned architecture | Stabilizes interaction and action lifecycle state without moving domain truth into the conversation layer |
| Life Context becomes the first shared authoritative context projection after the conversation boundary exists | Planned architecture | Reduces duplicated interpretation across planning, priority, and reasoning without owning conversational state |
| Reasoning consumes typed conversation state and typed Life Context projections | Planned architecture | Multi-domain reasoning depends on both inputs and must not replace deterministic domain engines |

## 19. Known architectural debt

Architectural debt is recorded here to prevent accidental normalization. It does not authorize unrelated refactoring.

### High priority

- The AI backend boundary is publicly callable and lacks the planned authentication, attestation, and request-validation layers.
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

## 23. Change policy for this document

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

## 24. Definition of architectural readiness

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

## 25. Enduring direction

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
