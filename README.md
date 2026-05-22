# Sous Chef AI — Native iOS

A native iOS port of [sous-chef-ai](https://github.com/djd39448/sous-chef-ai), an
AI-powered kitchen assistant for meal planning, recipe generation, and smart
shopping lists.

The original is a Replit-built web app (React / Express / PostgreSQL). This is a
full re-platform — **not** a code translation — onto a native stack:

| Layer | Original | This port |
|---|---|---|
| Frontend | React + Vite (web) | SwiftUI (native iOS) |
| Backend | Express + Node | Go |
| Database | PostgreSQL (Replit) | Supabase (PostgreSQL) |
| Auth | Replit Auth (OIDC) | Supabase Auth + Sign in with Apple |
| AI | OpenAI via Replit proxy | OpenAI directly |
| Hosting | Replit | AWS (backend), Supabase (data) |

## Method

The port preserves **behavior, not code**. Every layer is rewritten natively;
what carries over is the *contract* — the API surface and the Canonical Food
Object (CFO) data model. The three build tracks (backend, data, iOS) each build
against that single shared contract.

## Layout

```
contract/             The single source of truth — API spec, data model, AI behavior.
supabase/             Database schema as SQL migrations + row-level security.
backend/              Go REST API. Builds against contract/.
ios/                  SwiftUI app. Builds against contract/.
docs/PORT_PLAN.md     Phased roadmap, prerequisites, and the decisions log.
CODING_STANDARDS.md   Non-negotiable stack standard (sc-00 — sc-09).
BUILD_LOG.md          Phase-by-phase build progress, oldest first.
CHANGE_LOG.md         Decisions and pivots, newest first.
CLAUDE.md             Working rules + the docs-update protocol.
```

## Working rules

See [`CLAUDE.md`](CLAUDE.md) for the docs-update protocol — what to record
when, where, and why. The short version: the contract changes first; each
phase appends to `BUILD_LOG.md`; each pivot is a new entry in `CHANGE_LOG.md`.

## Status

See [docs/PORT_PLAN.md](docs/PORT_PLAN.md) for the phased roadmap and the
prerequisites checklist, and [`BUILD_LOG.md`](BUILD_LOG.md) for what's
actually built.
