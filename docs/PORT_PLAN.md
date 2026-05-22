# Port Plan — sous-chef-ai → native iOS

## Goal

Re-platform the Replit web app [`sous-chef-ai`](https://github.com/djd39448/sous-chef-ai)
into a native iOS app Dave can run on his iPhone, using a native stack
(SwiftUI + Go + Supabase).

## Approach

Three build tracks — **backend**, **data**, **iOS** — each build independently
against one shared **contract** (`contract/`). Build the contract first; it is
the only thing the tracks share.

## Phases

| # | Phase | Output | Gated on |
|---|---|---|---|
| 0 | Scaffold | Monorepo structure, this plan | — |
| 1 | Contract | `contract/` — API spec, data model, AI behavior | — |
| 2 | Data | `supabase/` — schema migrations + RLS | — |
| 3 | Backend | `backend/` — Go REST API, all endpoints, SSE, OpenAI | Go install, OpenAI key |
| 4 | iOS | `ios/` — SwiftUI app, 6 screens, Sign in with Apple | Xcode, Supabase project |
| 5 | Deploy | Backend on AWS, app running in iOS Simulator | AWS account |

## Prerequisites checklist

Phases 0–2 need nothing. The remaining phases need Dave to provide:

- [x] **Xcode** — installed (Xcode 26.5), after upgrading the Mac to
      macOS Tahoe 26.5 (the App Store Xcode requires macOS 26).
- [ ] **Supabase** — create an account and a new project (free tier). Provides
      Postgres + Auth. Needed to apply Phase 2 migrations and for Phase 4.
- [ ] **OpenAI API key** — a key with billing enabled. The original used Replit's
      OpenAI proxy, which is gone. Needed to run Phase 3 end-to-end.
- [ ] **AWS account** — for hosting the Go backend. Needed for Phase 5.
- [x] **Go toolchain** — installed (go 1.26.3).
- [ ] **Supabase CLI** — `brew install supabase/tap/supabase`. Needed to apply
      migrations. (Astra can install.)
- [ ] **Apple Developer account** — *not* needed for the Simulator. Needed only
      to run on a physical iPhone (free tier = 7-day signing; $99/yr = permanent).

## Decisions log

Deviations from a literal 1:1 port, and why.

- **D1 — Auth.** Replit Auth (OIDC + Passport) → Supabase Auth with Sign in with
  Apple. The `sessions` table is dropped (Supabase issues JWTs; no server-side
  session store). The `users` table becomes `public.profiles`, keyed to
  `auth.users.id`. All `user_id` columns become `uuid` referencing `auth.users`.
- **D2 — Dead tables removed.** The original `shared/models/chat.ts` defines
  `conversations` / `messages` tables that no route or storage method touches —
  the live chat uses `kitchen_conversations` / `kitchen_messages`. The dead pair
  is not carried into the new schema.
- **D3 — CFO consolidation deferred.** The original keeps legacy `ingredient_memory`
  and `shopping_list_items` tables and dual-writes them alongside the Canonical
  Food Object (`food_items`). This port preserves that behavior faithfully. The
  CFO spec intends lists to be *views* over `food_items`; collapsing the legacy
  tables into CFO projections is a worthwhile future cleanup but is **out of
  scope** for the port (it changes the `checked` state and free-text quantity
  handling — a refactor, not a translation).
- **D4 — AI access.** OpenAI is called directly with Dave's own key instead of
  through Replit's proxy. Model IDs and prompts are preserved as-is.

## Status

- **2026-05-22** — Phases 0–2 complete: monorepo scaffolded, contract authored,
  Supabase schema written.
- **2026-05-22** — Phase 3 complete: the Go backend (`backend/`) implements all
  25 endpoints, SSE streaming, Supabase JWT auth, and direct OpenAI integration,
  built against the contract. `go build`, `go vet`, and the unit test pass. Not
  yet exercised end-to-end — that needs a Supabase database URL and an OpenAI
  key (see prerequisites). Phases 4–5 pending.
- A contract clarification was made while building Phase 3: `GET
  /api/kitchen/conversation/:id` now follows the same ownership rule as every
  other `:id` endpoint (`403` for another user's row, `404` for missing) —
  the previous wording ("404 if not owned") contradicted the general rule.
