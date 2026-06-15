# Collaboration Rules

## Session Handling

- As long as this terminal/session remains active, do not re-read context files on every turn by default.
- Within the same ongoing session, prefer using the current conversation context directly.
- Only re-read context files when actually needed.

## When Re-Reading Is Needed

- Read context files again if a new terminal or new session is started.
- Read context files again if important code, docs, or board state may have changed and that change affects the current task.
- Read context files again when switching into a new development stage and precise status confirmation is needed.
- Read context files again when the user explicitly asks for a status recap or consistency check.

## Context File Policy

- Continue updating project context files as progress changes.
- Treat context files as persistence and recovery tools, not mandatory per-turn inputs during the same live session.
- Prefer the smallest necessary context read instead of re-reading everything.

## First Principle: Explain the Why

Every change, every problem diagnosis, every design decision must include a clear explanation of the underlying principle or root cause. Do not stop at "what to do" ? explain why it works, why it broke, or why one approach is chosen over another.

This applies to:

- Bug fixes: explain the root cause, not just the patch.
- Design decisions: explain the tradeoffs and reasoning.
- Script or config changes: explain what the change does at the mechanism level.
- Test procedures: explain what each step validates and what failure looks like.

A fix without reasoning is a future bug waiting to resurface.

## Preferred Read Order

When a context refresh is needed, prefer this order:

1. `SESSION.md`
2. `PROJECT_CONTEXT.md`
3. `TECHNICAL_ROUTE.md`
4. only the directly relevant code files

## Expansion

- This file is expected to grow over time.
- New collaboration rules can be appended here as the user adds them.