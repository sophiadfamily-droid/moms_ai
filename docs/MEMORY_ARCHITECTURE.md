# ZELIA Memory Architecture

## Status

This document describes the implemented Memory Lifecycle Engine V1. The
Firestore collection remains `users/{uid}/memories`; no migration or new
collection is required.

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

The broader Life Context construction still reads the existing memory stream
through `MemoryService`. Pagination or server-side relevance for that
pre-existing read path is deferred because it requires a wider retrieval
contract, not a lifecycle change.

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

## Deliberately deferred

- general contradiction and entity-resolution engines;
- probabilistic or model-based similarity;
- restoration workflow;
- complete memory-management UI;
- physical deletion and global Firestore migration;
- relations, priorities, consequences, and proactive anticipation.
