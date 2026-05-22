# Sous Chef

A native iOS port of the `sous-chef-ai` web app. This file is intentionally
thin — it points; it does not contain.

## Read first

- [`README.md`](README.md) — what this project is, and its layout.
- [`docs/PORT_PLAN.md`](docs/PORT_PLAN.md) — the phased build plan,
  prerequisites checklist, and the original decisions log (D1–D4).
  Authoritative for the roadmap.
- [`CODING_STANDARDS.md`](CODING_STANDARDS.md) — non-negotiable. The bar
  (`sc-00`): hand the codebase to any developer, say nothing, and they
  understand it without guessing.
- [`contract/`](contract/) — API spec, data model, AI behavior. **The
  contract changes first** whenever behavior changes; backend and iOS
  both build against it.

## Working rules

These are the docs-update protocol — followed on every change.

- **Follow `CODING_STANDARDS.md` on every change.** The `sc-09` checklist is
  the pre-commit gate.
- **Every new file carries its `sc-01` header** — what it does, what it
  depends on, what depends on it, why it exists. Stale headers are defects;
  fix them in the same commit you touch the file.
- **The contract changes first.** If a behavior must change, edit
  `contract/` before the backend or the iOS app. Both tracks build against
  it; neither track invents behavior on its own. Substantive contract
  changes also get a `CHANGE_LOG.md` entry.
- **Record progress in [`BUILD_LOG.md`](BUILD_LOG.md)** as each phase or
  work session completes. Chronological, oldest first; newest at the
  bottom. One paragraph minimum: what was built, what was verified, status.
- **Record pivots in [`CHANGE_LOG.md`](CHANGE_LOG.md)** the moment a
  direction changes — a workaround, a contract clarification, a deferred
  prerequisite, a deviation from the original. Newest first. Each entry:
  date, what changed, why. **Never silently edit docs to make a new
  direction look like it was always the plan.**
- **Commit small, with a clear `why`.** Imperative subject line under ~70
  chars; the body explains the *why*, not the *what* (the diff shows the
  what). Co-author Claude when applicable.
- **Secrets stay local.** `backend/.env` is gitignored; `.env.example`
  documents what is needed. No API key, service-role key, or `.p8`
  certificate ever lands in a tracked file.
- **Keep this file thin.** Durable knowledge goes into `PORT_PLAN`,
  `BUILD_LOG`, `CHANGE_LOG`, `CODING_STANDARDS`, or the contract — not
  here.

## When in doubt

If something doesn't fit a section above, ask before guessing. Cheap
clarification beats expensive rework.
