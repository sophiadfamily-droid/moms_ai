# ZELIA Repository Development Contract

This file is the operating contract for every human or AI agent working in this repository. It describes the repository as it exists; it is not a substitute for inspecting the current checkout. If this document and the implementation diverge, stop, inspect the relevant code and tests, and report the verified state before proposing an update to this contract.

## Mission and philosophy

ZELIA is a French-language AI assistant that helps a user manage family and personal life through conversation: profile and household context, tasks, shopping, calendar events, availability, travel, recurring routines, and durable memories. Its purpose is dependable assistance, not merely plausible text generation.

The project treats generated output as untrusted input. Deterministic application services validate, normalize, reason about, confirm, and persist actions. User context must improve assistance without overriding explicit facts, inventing constraints, or weakening privacy. Prefer transparent questions and confirmations over guessed dates, times, durations, travel, recurrence, or consent. Preserve established behavior unless a requested and reviewed change explicitly replaces it.

## Verified repository architecture

- `lib/main.dart` initializes Firebase and notifications, then drives onboarding and the Flutter application.
- `lib/screens/` contains onboarding, authentication, navigation, profile, chat, agenda, calendar, tasks, and shopping UI. `lib/screens/chat_screen.dart` currently coordinates the conversational workflow and pending action states.
- `lib/models/` defines the persisted/domain shapes for user profiles, events, tasks, shopping items, and planning drafts.
- `lib/services/` contains the client business logic. It includes local and cloud persistence, authentication, chat persistence, natural-language parsing, action guarding/handling, confirmation, conflicts, planning, memory, priorities, travel, notifications, and response construction.
- `functions/` is a Node.js 24 Firebase Functions codebase. `functions/index.js` exposes the HTTP chat function, assembles the ZELIA prompt context, detects intent and planning complexity, routes the model, calls the OpenAI Responses API, and returns strict `reply`, `actions`, and `memories` data.
- `functions/brain/` contains prompt identity/style/rules/dictionaries, response schemas, and server-side intent, memory, and planning helpers. `functions/services/` contains model routing and OpenAI integration.
- `test/` contains Flutter widget and Dart service tests. `functions/test/` contains Node tests for intent detection, planning complexity, model routing/integration, OpenAI response handling, and the strict response schema.
- Platform folders (`android/`, `ios/`, `web/`, `macos/`, `linux/`, and `windows/`) contain Flutter platform integration. `assets/` contains application images. `archive/legacy_sources/` is historical material, not the active implementation.

This codebase currently has some similarly named Dart and JavaScript engines. Do not assume they are interchangeable or consolidate them without tracing their actual callers and contracts.

The architecture, Firebase project and database/region, Functions runtime, and other repository-specific facts above are a verified snapshot from when this contract was created. Recheck them against the current checkout before relying on them, especially before any configuration or approved remote work.

## Engineering and coding rules

1. Inspect the current repository before coding. Never modify code from memory, assume a class or field name, or invent architecture.
2. Trace the caller, implementation, data model, persistence boundary, and relevant tests before changing behavior.
3. Make the smallest coherent change. Preserve public shapes, stored data, legacy fallbacks, UI wording semantics, and backward compatibility unless an approved migration says otherwise.
4. Keep business rules in the appropriate service/engine. Do not duplicate them in screens, prompts, tests, or parallel helpers, and do not scatter hardcoded business rules through UI code.
5. Reuse existing models and services. Search before adding a class, parser, normalizer, constant, or persistence path.
6. Treat AI responses, user text, stored legacy data, and remote data as boundary inputs requiring validation and safe defaults. Never silently turn missing or invalid information into a fabricated fact.
7. Follow `analysis_options.yaml`, existing Dart style, existing CommonJS/ESLint style in `functions/`, and the established language and tone of user-facing copy.
8. Do not modify generated platform configuration or dependency lockfiles unless the requested change requires it and its consequences have been inspected.
9. Never silently change behavior. State intentional behavior changes, compatibility effects, and validation evidence in the handoff.

## Planning engine contract

Planning is a pipeline, not a single class. Inspect at minimum the relevant parts of `PlanningDraftService`/`PlanningDraftModel`, `PlanningProposalService`, `PlanningProposalEngine`, `SmartPlanningService`, `PlanningWindowService`, `PlanningScoreService`, `EventService`, `ConflictEngineService`, `SelectedSlotScheduleService`, `SelectedSlotRevalidationService`, `EventConfirmationService`, profile and memory reasoning, recurrence matching, and travel metadata before modifying it.

- Preserve the collect → propose → select → revalidate → confirm → write sequence where applicable. A proposal is not authorization to create an event.
- Never fabricate user confirmation. Event writes must occur only after the established explicit confirmation path.
- Do not invent a duration, date, time, travel time, recurrence, margin, or availability constraint. Missing required information remains missing and should trigger the established question flow.
- Preserve separate outbound and return travel values, explicit zero values, safety margins, protected time ranges, and compatibility with legacy combined travel data.
- Conflict checks must consider full protected ranges. A selected proposal must be revalidated against current events before persistence.
- Preserve structured profile and memory constraints, their applicable dates/days, recurrence anchors, and the distinction between a hard blocked period and a preference. Do not reintroduce generic family/evening or other inferred blocks.
- Preserve option deduplication, day diversification, scoring, planning windows, and recurrence behavior unless the requested change deliberately updates them with regression coverage.
- Centralize date/recurrence matching and business decisions in existing services rather than reproducing keyword or calendar logic in screens or prompts.

## Memory engine contract

Memory handling spans `MemoryEngineService`, `MemoryPipelineService`, `MemoryService`, `MemoryContextBuilderService`, `MemoryRetrievalService`, `MemoryReasoningService`, `MemorySimilarityService`, `MemoryConsolidationService`, `RecurringMemoryScheduleService`, and server prompt/rule inputs. Trace the live chat call path before changing any of them.

- Store durable user facts, preferences, constraints, and recurring routines according to the existing eligibility and categorization rules; do not turn transient tasks, appointments, or conversational guesses into durable memory.
- Preserve normalization and duplicate prevention. On uncertainty or persistence errors, prefer not writing over creating duplicate or invented memory.
- Preserve the memory payload contract (`text`, category, importance, and applicable creation metadata), legacy compatibility, importance ordering, and bounded context selection.
- Preserve `createdAt`/`createdAtIso` through context building because recurring and biweekly routines may use the creation date as their anchor.
- Preserve the conversion of eligible recurring memories into dated blocked periods, including weekday, weekly, and biweekly matching, complete time ranges, travel boundaries, and non-applicable days.
- Keep memory extraction, persistence, retrieval, reasoning, and consolidation distinct. Do not duplicate keyword tables or scheduling interpretations without first identifying the authoritative implementation.
- Never claim that a memory was saved, changed, or deleted unless the corresponding operation actually succeeded.

## Firebase and security contract

The repository is already configured for Firebase project `zelia-ai-app`. `firebase.json` targets the `(default)` Firestore database in `eur3`, the `functions` codebase, Hosting from `public/`, and Storage rules. Platform configuration is present in `lib/firebase_options.dart`, Android, and iOS. Inspect all current configuration before making any recommendation.

- Never recommend creating a Firestore Enterprise database merely because generic documentation or the example comments in `firestore.indexes.json` mention Enterprise. The configured database is `(default)`; verify actual requirements and obtain approval for any database-level change.
- Never change the Firebase project, database, region, rules, indexes, functions, hosting, storage, app registration, or secrets without explicit developer approval.
- Never execute a remote Firebase command—including deploy, project selection/change, remote logs, configuration, secrets, database, or rules operations—without explicit approval. Local static inspection and approved emulator use are distinct from remote operations.
- Current Firestore rules require authentication and restrict `/users/{userId}` plus all descendants to that same UID; all other document access is denied. Current Storage rules deny all reads and writes. Do not weaken either boundary casually.
- Keep user data under authenticated user ownership. Inspect `AuthService` and each cloud service before changing collection paths or access patterns.
- Never commit or expose credentials, API keys, Firebase secrets, tokens, private user data, or logs containing sensitive content. The Functions API key is supplied through the `OPENAI_API_KEY` secret.
- Validate and normalize generated actions through the existing strict server schema and client action guard. Preserve least privilege, fail-closed behavior, and bounded numeric inputs.

## Git rules

Without explicit developer approval, never commit, push, reset, rebase, amend, force-update, delete a branch, or change branches in a way that risks work. Do not discard, overwrite, or “clean up” unrelated changes. Inspect `git status --short`, relevant diffs, and recent commits before editing. Ask for confirmation before every destructive action and identify its exact target and recovery implications. Never fabricate approval or infer it from a request to edit code.

## Testing and regression policy

Tests are executable contracts. Read existing tests before implementation, add or update focused regression tests for every intentional behavior change, and do not weaken assertions simply to make a change pass.

Use the checks relevant to the changed area:

```sh
flutter analyze
flutter test
cd functions && npm run lint
cd functions && node --test test/services/*.test.js
```

`functions/package.json` currently defines the official `lint` script but no `test` script; the Functions test command above directly runs the repository's existing `functions/test/services/*.test.js` files with Node's test runner. Reinspect the package scripts before future use and prefer an official test script if the repository adds one.

Also run the narrowest affected test first while iterating. Do not run deploy scripts as validation. If tooling, permissions, dependencies, or environment limitations prevent a check, report the exact command and failure; never report an unrun test as passing.

At minimum, planning changes must protect proposal diversity, structured windows/constraints, recurrence applicability, school schedules, conflicts, selected-slot revalidation, explicit confirmation, travel and margin boundaries, and legacy event compatibility. Memory changes must protect eligibility, categorization, deduplication/consolidation, payload normalization, timestamp propagation, relevant context, recurring blocked periods, and recurrence anchors. Server changes must protect intent/complexity classification, model routing, strict schema compatibility with Flutter, parsing, and bounded fallback behavior. UI changes must retain the relevant widget/navigation coverage.

A regression is any unintended change to behavior, data shape, stored-data readability, confirmation semantics, planning availability/scoring, memory interpretation, security rules, or client/server schema compatibility. Fix regressions at their source; do not mask them with broader defaults or looser tests.

## Repository workflow and modification protocol

1. Restate the requested outcome and its boundaries. Identify actions requiring separate approval.
2. Perform the repository inspection protocol below and note pre-existing working-tree changes.
3. Trace the real execution and data flow; identify the authoritative services, models, schemas, configuration, and tests.
4. Explain uncertainty using verified current state. Ask before destructive, remote, security-sensitive, migration, or behavior-changing action not already authorized.
5. Plan a minimal change and its regression coverage. Check for reusable logic before creating anything new.
6. Implement only in scope. Preserve unrelated user work and backward-compatible readers/writers.
7. Run formatting, static analysis, focused tests, then the appropriate broader suite.
8. Review `git status --short` and the complete diff. Remove only artifacts created by the current task, safely.
9. Hand off changed paths, behavior, tests and results, known limitations, and any approval-dependent next step. Do not commit, deploy, or perform remote operations unless separately approved.

## Repository inspection protocol

Before modifying code:

- Confirm the repository root and read the nearest applicable `AGENTS.md` files.
- When `docs/` exists, inspect the approved ZELIA documentation relevant to the task, then verify it against the current code and tests rather than treating it as a replacement for repository inspection.
- Inspect `git status --short`, the relevant diff, and recent `git log` entries. Preserve pre-existing changes.
- Map the relevant directories and search for actual symbols and callers; never assume names or rely on remembered architecture.
- Read the entry point, relevant screens, models, services/engines, schemas/prompts, persistence code, and configuration.
- Read all tests directly related to the requested behavior, plus adjacent regression tests and recent commits affecting that area.
- For Firebase work, inspect `.firebaserc`, `firebase.json`, Firestore indexes/rules, Storage rules, platform options, Functions configuration, and the affected authenticated data paths before recommending changes.
- Verify client/server field contracts when a change crosses the Flutter/Functions boundary.

## Validation checklist before modifying code

- [ ] The requested scope and prohibited actions are clear.
- [ ] Current working-tree changes and recent relevant commits are understood.
- [ ] Real callers, implementations, models, persistence paths, and tests have been inspected.
- [ ] No class name, field, collection, user confirmation, or architectural layer has been assumed.
- [ ] The authoritative location for the business rule is identified; duplication and hardcoding are avoided.
- [ ] Backward compatibility, planning behavior, memory behavior, security, and schema effects are understood.
- [ ] Required approval has been obtained for any destructive, remote, deployment, Firebase-project, migration, or Git operation.
- [ ] A focused test and validation plan exists.

## Validation checklist after modifying code

- [ ] The final diff contains only requested, intentional changes and no generated or unrelated artifacts.
- [ ] Existing behavior is preserved except for explicitly requested and documented changes.
- [ ] Planning confirmation, conflicts, revalidation, recurrence, travel, margins, and legacy compatibility still hold where relevant.
- [ ] Memory eligibility, deduplication, timestamps, recurrence anchors, context, and legacy compatibility still hold where relevant.
- [ ] Firebase ownership boundaries and deny-by-default rules are not weakened; no project or remote state changed without approval.
- [ ] Client/server schemas remain aligned and untrusted data remains validated.
- [ ] Formatting, analysis, lint, focused tests, and relevant full suites were run, or each limitation is reported exactly.
- [ ] `git status --short` and the complete relevant diff were reviewed.
- [ ] No destructive action, fabricated confirmation, silent behavior change, commit, push, or deployment occurred without explicit approval.
