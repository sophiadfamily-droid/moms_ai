# Life Context Engine V1

This engine implements the shared context required by
`docs/ZELIA_BRAIN_CONTRACT.md`. In particular, it must distinguish another
person's schedule from a consequence that actually occupies the primary user.

## Ownership

Life Context is the reconstructible, read-only representation of the current
account context. It does not own HumanModel, Identity, Event, Task, Routine or
Memory records and never persists a snapshot or projection.

The production chain is:

```text
authenticated account scope
  → six canonical domain adapters
  → LifeContextSnapshot (LC.1)
  → LifeContextRelationEngine (LC.2)
  → LifeContextProjectionEngine + consumer contract (LC.3)
```

`LifeContextProduction` is the single coordinator for this chain. It keeps one
immutable generation for the active account, serializes refreshes and rejects
late results after an account change.

## Availability semantics

A routine or commitment belonging to the primary person may protect time in
Planning. A routine belonging to another person is contextual information and
must not become a blocker merely because it exists.

Another person's commitment can affect availability only through a typed,
evidenced consequence for the primary person, such as participation,
preparation, transport, waiting, replacement or a temporally relevant
responsibility. Broad relationship labels and generic responsibility links do
not justify blocking the other person's complete schedule. A responsibility
also remains non-blocking unless it is confirmed, names the primary person as
responsible, has a closed planning kind (accompaniment, transport, care or
daily assistance), and carries an explicit start and end no more than 24 hours
apart.

The first migration slice therefore preserves other-person routines in Life
Context while excluding their full ranges from primary-person blockers. The
second slice projects an explicitly declared, time-bounded responsibility as
its own primary-person commitment without inferring it from the other
person's schedule. The third slice supports an explicitly confirmed weekly
consequence with civil weekdays and local start/end times. It blocks only the
short recurring participation, transport, preparation, waiting, replacement
or care range carried by the primary person; it never turns the subject's full
school, work or activity range into the primary person's unavailability.

Conversation can now create that weekly consequence from a bounded explicit
first-person statement. The deterministic local path resolves a known person,
collects only a missing time range or disambiguating name, and writes through
`HumanModelEditService` after one yes. It is deliberately evaluated before
generic Routine creation, so “I take Alex every Monday…” becomes a confirmed
responsibility rather than a personal activity. Questions, tentative language,
third-person schedules and unconfirmed relationship assumptions do not enter
this write path.

The profile-derived school drop-off clarification follows the same boundary.
It never appears merely because Chat was opened. School hours reveal that a
transition may be missing, so Zelia may ask once who usually handles drop-off
only when a dated Event request actually touches that entry transition. After
the answer, the suspended Event request resumes automatically. Before a yes
there is no planning consequence. After a yes, an explicit one-way travel
duration protects only the journey to school and the return from it around the
entry time. When that duration is still unknown, the known school-entry
instant is nevertheless projected as a one-minute technical marker: this
makes a request placed exactly at the confirmed transition detectable without
fabricating a commute duration. Existing confirmations that predate this
marker are completed silently from the current school schedule and are never
asked again. A no is remembered and does not resurface. The child's full
school period always remains non-blocking for the primary person. Failure to
load this optional question must not interrupt the Event request.

One dated Routine exception is not a new recurrence. Canonical
`RoutineOccurrenceOverride` records are applied by the Routine Occurrence
Engine before its results enter Life Context or Planning: cancellation and
entity-linked replacement suppress only the named source occurrence, a labelled
replacement remains visible as the exceptional commitment on that date, and a
move projects that same stable occurrence at its explicit destination. The
recurring Routine and all following occurrences remain intact. Conversation
creates an override only after resolving one real applicable occurrence and
receiving explicit confirmation; it never converts a whole-series or Event
request into an occurrence exception.

Agenda is a read-only projection of this same schedule reality. Structured
Profile activities, work ranges, school ranges and household-person activities
are adapted to stable technical Routine identities for projection and dated
overrides only; they are not copied into Events. Agenda displays every valid
range with a short human kind, but conflict detection still follows the user
consequence rule above. Thus a child's school range can be visible in the day
without declaring the primary user unavailable.

## Seven consumer sections

| Section | Canonical source |
| --- | --- |
| Human | revisioned, account-scoped HumanModel |
| Identity | confirmed Identity links already attached to HumanPerson |
| Event | account-bound Event read facade |
| Task | account-bound revisioned Task read facade |
| Routine | confirmed Routine records plus the bounded legacy compatibility source |
| Memory | policy-filtered, non-tombstoned Memory records |
| Relation | LC.2 graph derived only from the same LC.1 snapshot |

Each source metadata contract exposes schema version, availability, source
revision when present, read/generation time, freshness, account-scope match,
entity count, truncation state and closed warning codes.

### Profile and Human ownership

`users/{uid}/private/profile` contains only the revisioned Profile-owned
settings. Names, birth dates, people and explicit relationships are written to
`users/{uid}/private/humanModel`; relations are embedded in that canonical
aggregate and are not duplicated in a second collection. The profile editor
updates both owners through their existing services. On authenticated
bootstrap, the display-compatible `UserProfile` is reconstructed from the
cloud Profile and HumanModel without treating an empty Profile-owned payload
as evidence that a person or relationship was removed.

Identity documents remain separate and are created only through their explicit
identity workflow. A name entered in Profile never creates an Identity link by
inference. Conversation may project an active related person's name only when
an explicit active HumanModel relationship connects that person to the primary
person.

## Availability and global state

`empty` means a successful read with no records. It is not an error.
`availableStale` retains known data but does not claim that it is current.
`unavailable`, `corrupted`, `unsupported` and `accountMismatch` fail closed.
Material source truncation remains explicit.

The LC.1 state is `complete`, `partial` or `unavailable`. Empty healthy
sections permit `complete`. Any stale or materially truncated section produces
`partial`; all sources blocked produces `unavailable`. LC.3 preserves these
signals and never turns a missing source into an empty list.

## Freshness and invalidation

Freshness uses an injected clock and centralized maximum ages:

- Human and Identity: 15 minutes;
- Event and Task: 2 minutes;
- Routine and Memory: 5 minutes.

A fresh generation is reused. Task and Event mutations invalidate their own
section. Human invalidation also invalidates Identity and Routine because both
derive part of their state from HumanModel. Confirmed Routine writes and
Memory lifecycle writes invalidate their corresponding sections. The typed
`invalidateSection` boundary remains available for future mutation owners.
Account changes invalidate every section and increment the account generation.

There is no polling, permanent timer or rebuild-triggered reload.

## Source and projection budgets

Source adapters are bounded before the immutable snapshot:

- Event: 200 records;
- Task: 200 records;
- Routine: 200 records;
- Memory: 500 consumable records.

Selection is deterministic by stable technical fields. LC.3 then applies its
separate global and per-section budgets. Exceeding either boundary records
truncation and prevents a false complete projection. Long free text remains
excluded whenever the consumer contract does not permit it.

## Capability compatibility

Global state remains visible, but a closed capability check avoids blocking an
unrelated safe read:

- Conversation requires Human;
- Priority requires Task;
- Planning requires Event and Routine;
- Memory reasoning requires Memory.

A required stale, unavailable, corrupt, unsupported or account-mismatched
section blocks that capability. A degraded unrelated section may leave the
capability usable with an explicitly partial global context. This does not
authorize an action or fabricate a missing fact.

Consumers may add scenario-specific requirements without changing the closed
base contract. Task-originated Smart Planning additionally requires Task;
Human, Identity and Relation are required only when a stable person reference
is actually part of the request. Compatibility reports required, available
and blocking domains, warning codes and the exact source generation as a
single typed result.

## Consumers

Conversation, Priority consultation, proactive Priority, deterministic
proactive detection, the production Smart Planning gateway and Memory
Reasoning consume the same production generation. Each receives its own
bounded adapter contract.

`LifeContextPlanningProjectionAdapter` preserves protected Event periods,
separate travel directions, margins, recurrence, revisions and confirmed
Routine periods. A proposal freezes its source generation and final
confirmation revalidates the selected slot against the current Event and
Routine constraints.

`MemoryReasoningContext` is built only from the canonical Memory section.
Confirmed active records are deterministically ordered; proposed, rejected,
superseded, expired, ambiguous and explicit-health records are excluded.
Planning sees only the narrower recurring-Routine compatibility result, never
free Memory text interpreted as a constraint.

## Diagnostics

Diagnostics use `component: life_context` and closed steps such as `refresh`
and `reject_stale_result`. They may contain counts, availability, revision,
generation, duration and warning codes. They never contain account IDs, names,
relations in readable form, titles, memories, locations, planning details or
payloads.

## Current limitations

- HumanModel remains the bounded single-document aggregate defined by HM.2.
- Routine still contains a documented legacy-profile compatibility source.
- Identity is limited to already persisted HumanPerson links.
- Task has no structured cross-domain LC.2 relationship.
- Person-specific Planning cannot require Relation until the initiating domain
  carries a stable person reference; no name-based matching is introduced.
- Legacy Planning and Memory adapter entry points remain only for callers not
  yet migrated and explicit compatibility tests.
