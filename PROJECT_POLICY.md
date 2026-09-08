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

The active first sprint is capture reliability plus removal of fabricated export values, including the persistence repairs needed for trustworthy capture. Establish regression evidence, implement the fix, independently review the change, verify it, and carry it through integration.

Preserve on-device runtime, complete file protection, event-sourced clinical state, operator review authority and truthful unknown values. Model/backend expansion and optional hardware experiments follow a reliable capture-to-documentation path. The iPhone remains a primary development target; the pocket Constellation experiment is out of scope.

## Continuation

Read AGENTS.md, CLAUDE.md and this policy, then check current Git state and the active sprint plan. Historical inventories, test counts and chat instructions are evidence from their dates, not current blockers or proof of readiness. Do not restart completed preservation work simply because an old note says to begin read-only.

The active iOS repository is `aarzamen/TCCC_IOS`. The older Python recovery repository and Constellation are separate repositories; preserve their provenance and do not combine their files or histories into the iOS repository.

<!-- The user explicitly retired the completed non-destructive review and assigned
GPT-6 ownership of leadership, planning and architecture, with authorization to
commit, push and publish all project changes. This policy prevents an obsolete
recovery-stage restriction or unavailable worker from repeatedly stopping work. -->
