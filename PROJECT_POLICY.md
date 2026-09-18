# TCCC project ownership and execution

Effective 2026-09-08, by the user's explicit instruction in the TCCC project conversation. This is the current project workflow policy; earlier read-only recovery instructions and approval-only integration rules are superseded.

## Ownership

GPT-6 in the lead Codex conversation owns engineering leadership: priorities, planning, architecture, implementation decisions, worker coordination, verification, Git integration and repository publication. The user retains product direction and repository ownership.

Codex may implement directly or assign bounded work to native Claude Code and other available workers. Workers operate under Codex's scope and review; no worker has independent authority to change project direction. Claude availability or authentication is not a prerequisite for development. The prior requirement that only native Claude author code/tests is retired.

## Standing authorization

The user authorizes implementing project changes, running checks, creating branches/worktrees, committing, pushing, opening and merging pull requests, updating main, and publishing project source, documentation and validated release artifacts to the existing repository. Complete routine integration without asking for renewed approval at each step.

Commit and push project work as coherent, reviewable changes. Preserve unfinished work on an explicitly described development branch; integrate into main when the relevant checks and review support it. Never describe a failing checkpoint as a validated release.

This policy records user authorization. It does not change operating-system permissions, tool sandbox rules, account access, or repository protection settings. If a platform blocks an authorized operation, identify the actual block and continue unaffected work.

Repository publication covers project material. Keep patient data, personal recordings, credentials, device backups and private conversation exports out of Git and release artifacts. Preserve the existing repository visibility unless the user requests a visibility change. Do not force-push shared history or delete preservation archives as routine cleanup.

## Priority and architecture

Sprint direction (2026-09-08): target a technically worthwhile, presentable iOS
demonstration for the NMRTU Navy research/development medical technology team
in roughly one to two weeks. This is a solo-development project; Codex handles
GitHub housekeeping without turning routine Git choices into user tasks.
Deliver coherent feature slices. Use focused regression checks and one
integration review, expanding validation only for actual failures or material
unresolved risks. Reuse existing preservation and evidence; do not repeat
inventories, backups or approval ceremonies by default. Favor working progress.

Current direction (2026-09-18): local wireless vitals integration, starting with
the Vibeat S5W pulse oximeter, is the next main development priority. Capture
reliability, truthful export values, and their persistence protections remain
requirements throughout this work. Establish regression evidence, implement
the change, independently review it, verify it, and carry it through integration.

Preserve on-device runtime, complete file protection, event-sourced clinical state, operator review authority and truthful unknown values. Wireless sensor work must use the reliable capture-to-documentation path. The iPhone remains a primary development target; the pocket Constellation experiment is out of scope.

## Local wireless vitals (2026-09-18)

The owner explicitly authorizes local Bluetooth sensor communication on iOS,
superseding the former blanket no-Bluetooth / RF Ghost constraint. Offline now
means no internet dependency for capture and sensor use, not that every radio
is disabled. This does not authorize cloud services, vendor accounts or apps
at runtime, telemetry, analytics, automatic uploads, or unrelated wireless
features. ASR and language-model inference remain on-device; existing
operator-gated model preparation remains unchanged.

Required behavior: Settings/options includes a persistent pulse-oximeter
auto-connect control, enabled by default. When enabled, quietly discover and
attempt connection to a supported oximeter and reconnect after recoverable
disconnects. Respect OS permissions, Bluetooth state, and actual iOS
background-execution limits. Avoid alert spam and ambiguous device selection;
expose connection and data status in Settings. Turning the control off stops
scanning, pending connections, retries, and sensor ingestion. Required sensor
connection, selection, and provenance controls are permitted operational UI;
clinical displays still follow the DD 1380 / MARCH / PAWS rubric.

Sensor facts must retain device/raw-frame provenance in the event-sourced
encounter, preserve unknown and invalid values truthfully, and remain labeled
as unvalidated consumer-sensor measurements. A connection is not proof of a
valid reading. Keep private bench captures and personal readings outside Git.

The owner authorizes updating the default branch directly for this direction.
Its actual name is `main` (the owner referred to it as master); no branch rename
is requested. Scoped worker isolation remains available when useful.

These are approved requirements, not a claim of implemented or device-verified
support. Follow the [wireless vitals direction](docs/superpowers/specs/2026-09-18-wireless-vitals-direction.md)
for protocol verification, integration boundaries, and acceptance evidence.

## Continuation

Read AGENTS.md, CLAUDE.md and this policy, then check current Git state and the active sprint plan. Historical inventories, test counts and chat instructions are evidence from their dates, not current blockers or proof of readiness. Do not restart completed preservation work simply because an old note says to begin read-only.

The active iOS repository is `aarzamen/TCCC_IOS`. The older Python recovery repository and Constellation are separate repositories; preserve their provenance and do not combine their files or histories into the iOS repository.

<!-- The user explicitly retired the completed non-destructive review and assigned
GPT-6 ownership of leadership, planning and architecture, with authorization to
commit, push and publish all project changes. This policy prevents an obsolete
recovery-stage restriction or unavailable worker from repeatedly stopping work. -->
