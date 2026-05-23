# Sous Chef — Build Log

A chronological record of build progress, phase by phase. **Oldest first;
newest at the bottom.** Each entry notes the date, the phase, what was done,
and status.

For *why* a direction changed, see [`CHANGE_LOG.md`](CHANGE_LOG.md).

---

## 2026-05-22 · Planning

Approach worked out collaboratively: re-platform the Replit web app
`sous-chef-ai` (React + Express + Postgres) into a native iOS app on a clean
stack — SwiftUI iOS + Go backend + Supabase + AWS. Method: port **behavior**,
not code, through three parallel tracks (backend, data, iOS) converging on one
shared **contract**. Decisions D1–D4 (Replit Auth → Supabase Auth + Sign in
with Apple; dead chat tables removed; CFO consolidation deferred; OpenAI called
directly) recorded in `docs/PORT_PLAN.md` and `CHANGE_LOG.md`.

---

## 2026-05-22 · Phase 0 — Scaffold the monorepo ✅

Repo skeleton: `backend/`, `ios/`, `supabase/`, `contract/`, `docs/`, each with
a README pointing into the live `docs/PORT_PLAN.md`. Root `README.md`,
`.gitignore` (env files, macOS / Xcode / Go cruft). Initial commit `85eee85`.

---

## 2026-05-22 · Phase 1 — Write the shared contract ✅

`contract/` authored as the single source of truth:
- `api-spec.md` — every HTTP endpoint (25 in all), the auth convention, the
  object shapes, SSE event formats, ownership rules.
- `data-model.md` — every table, the Canonical Food Object (CFO) JSONB shapes,
  constraints, the dormant `recipes` table and the legacy `ingredient_memory`
  / `shopping_list_items` (Decision D3).
- `ai-behavior.md` — models, parameters, every system prompt verbatim, the
  three chat tools + `update_meal`, meal-plan and shopping-list generation
  flows including the deterministic fallbacks.
- `README.md` — the rule that the contract changes first.

---

## 2026-05-22 · Phase 2 — Supabase schema + RLS ✅

Two SQL migrations under `supabase/migrations/`:
- `20260522000000_initial_schema.sql` — 11 tables, the `set_updated_at`
  trigger, the `handle_new_user` profile-creation trigger, the CFO identity
  unique index `(user_id, canonical_name, (usage_context->>'role'))`, the
  per-week unique indexes for plans and shopping lists.
- `20260522000100_rls_policies.sql` — RLS enabled on every table, one policy
  per owner, child tables checked through their parent.

Phases 0–2 committed together as `b6c05c2` ("Scaffold port: monorepo, shared
contract, Supabase schema").

---

## 2026-05-22 · Phase 3 — Go backend ✅

A from-scratch Go rewrite of the original Express server, built against the
contract. Module `souschef` at `backend/`, Go 1.26.

- **API.** All 25 endpoints under `/api/`, plus an unauthenticated `/healthz`.
  Method+path routing on the stdlib `http.ServeMux`. Custom `NavBar`-style
  ownership errors (`403` for not-owned, `404` for missing, `400` for bad ids).
- **SSE.** Streaming for `POST /api/kitchen/message`, `generate-recipe/:dayId`,
  and `recipe-message`. Pre-flight validation runs before the SSE headers; once
  the stream opens, errors arrive as `data: {"error":"..."}`.
- **Auth.** Supabase JWT middleware (HS256 against the project JWT secret);
  the `sub` claim becomes `userId` on the request context. `/healthz` is
  exempt for load-balancer probes.
- **OpenAI.** Minimal hand-rolled client (`internal/openai/`): streaming chat
  completions with tool calls accumulated by index, JSON-mode for meal-plan /
  shopping-list generation, `gpt-image-1` for food photos. Tool calls execute
  silently server-side; the client refetches affected resources after the
  stream ends — exactly the contract behavior.
- **Tools.** `update_ingredients` (add/remove, with CFO upsert + ingredient
  memory dual-write per D3), `create_meal_plan` (replaces the current week),
  `create_shopping_list` (per-item CFO + shopping_list_items), `update_meal`
  (recipe swap).
- **Data layer.** `pgx/v5` with `pgxpool`. The CFO upsert uses
  `ON CONFLICT (user_id, canonical_name, (usage_context->>'role'))` matching
  the schema's expression unique index.
- **Tests.** The week-start helper (Monday-of-week, reproducing the original
  `getWeekStartDate()`) has a unit test in `internal/api/weekstart_test.go`.
- **Verification.** `go build ./...`, `go vet ./...`, `go test ./...` all
  clean. **Not yet exercised end-to-end** — that needs a Supabase database URL
  and an OpenAI API key (the "Verify backend end-to-end" task).

Two contract touch-ups landed in the same commit, both recorded in
`CHANGE_LOG.md`: ownership for `GET /api/kitchen/conversation/:id` was
unified with the general 403/404 rule; the `cookbookContext` placeholder in
the meal-plan generation prompt was documented.

Committed: `2fe25a3` (33 files, +3417).

Follow-up the same day: a small Go migration runner at
`backend/cmd/migrate/main.go` so the project doesn't need the Supabase CLI to
apply schemas. Committed: `ef81688`.

---

## 2026-05-22 · Phase 4 — SwiftUI iOS app ✅

The full SwiftUI app, built from the *Sous Chef iOS* design handoff bundle
(claude.ai/design — fetched as `https://api.anthropic.com/v1/design/h/…`). The
design specifies 8 screens with a warm culinary aesthetic (cream / terracotta
/ sage, serif display + SF Pro body) and a custom frosted tab bar.

- **Project.** `ios/SousChef.xcodeproj` is hand-written using Xcode 16's
  file-system-synchronized target — every `.swift` file under `SousChef/` is
  picked up automatically, no per-file pbxproj entry. Deployment iOS 17,
  Swift 5, no third-party dependencies.
- **Design system.** `Theme.swift` ports the palette verbatim from the
  prototype's `shared.jsx` by writing a `Color.init(oklch:_:_)` that does the
  OKLCH → OKLab → linear sRGB → gamma sRGB conversion. Display font uses the
  system serif (New York) — see `CHANGE_LOG.md` for the Fraunces decision.
- **Components.** `SCIcon` (SF Symbol mapping), `IconButton`, `Chip`,
  `PrimaryButton`, `NavBar`, `FoodImage` (AsyncImage with a gradient
  placeholder), `CatDot`, `Hairline`, and a `.cardSurface(_:)` view modifier.
  `FlowLayout` (a `Layout` for the pantry wrap) lives with `HomeScreen`.
- **Screens** (`SousChef/Screens/`): SignIn, Home, Plan, Calendar, Cookbook,
  Recipe, Shopping, Chat — all 8 from the design.
- **Navigation.** `RootView` gates on a mock `signedIn` state. `MainView`
  holds 5 tabs, each its own `NavigationStack`, behind a custom
  `CustomTabBar` (`.ultraThinMaterial` + cream tint, terracotta active).
  Calendar pushes onto Plan's stack; Recipe presents as a `fullScreenCover`
  so it covers the tab bar.
- **Interactions.** Shopping checkbox toggle with a sage progress bar; recipe
  ingredient toggle with strike-through; calendar segmented control switching
  plans / lists; chat composer appends to the local message list. All other
  taps are static, matching the prototype.
- **Verification.** `xcodebuild` for the iOS Simulator built clean (zero
  warnings). The app was booted on an iPhone 17 Pro simulator, installed,
  launched, and screenshotted on the SignIn screen. A first run caught two
  visible bugs (the `Text("Sous\n") + Text("Chef")` concatenation truncating
  to one line, and the Terms text similarly collapsing) — both fixed with an
  explicit two-line `VStack` and `fixedSize(horizontal:vertical:)`. A second
  screenshot from Home, taken after temporarily flipping `signedIn = true`,
  confirmed the design system, AsyncImage loading, day strip, and the custom
  tab bar all render correctly.

Committed: `5a1e30b` (21 files, +2524) plus `d5b5fff` for the SignIn fix.

Phases 5 (deploy + on-device) and the backend end-to-end verification remain
— both gated on the Supabase project, OpenAI key, and an AWS account.

---

## 2026-05-22 · Backend end-to-end: first Supabase connection ✅ (partial)

The Sous Chef Supabase project was provisioned and its values landed in a
local note; they were transcribed into `backend/.env` (gitignored). The
project ref is `hssqzhwtwpvblfdmqzpw`. A first screenshot pass had a
two-character OCR error (`a`↔`q` in the ref, `l`↔`I` in the publishable
key), caught when Dave pasted the Supabase Next.js quickstart values back
verbatim.

- **Schema applied.** `go run ./cmd/migrate ../supabase/migrations` ran both
  `20260522000000_initial_schema.sql` and `20260522000100_rls_policies.sql`
  against the live Supabase database — 11 tables, the CFO identity unique
  index, the per-week unique indexes for plans and shopping lists, the
  `set_updated_at` and `handle_new_user` triggers, and RLS enabled on every
  table.
- **Server boots and connects.** `go run ./cmd/server` started, `pgx`'s
  `pool.Ping` succeeded, the server listened on `:8080`.
- **`/healthz` → 200 ok.** Unauthenticated probe passes.
- **JWT middleware gate works.** `GET /api/auth/user` without a token →
  `401 {"error":"unauthorized"}`.

Still pending — the *verification* part of the task:
- **JWKS auth update** (CHANGE_LOG: asymmetric JWT signing keys). The
  current HS256 middleware can't verify the project's asymmetric tokens —
  `SUPABASE_JWT_SECRET` is a placeholder so the server boots, but no real
  Supabase Auth token will validate against it. Next backend change.
- **OpenAI call** — not yet exercised. (Also: the OpenAI key was
  transcribed from a screenshot and likely has a similar `I`/`l` error;
  Dave to verify.)

---

## 2026-05-22 · Backend end-to-end: pooler + OpenAI key verified ✅

Two follow-ups to the first-connection entry above, in the same session:

- **Switched `DATABASE_URL` to the Session pooler.** Dave provided the
  full pooler URI from the Supabase dashboard's Connect dialog:
  `aws-1-us-east-1.pooler.supabase.com:5432`. That's the IPv4-proxied
  Supavisor endpoint Supabase recommends for app code (the direct
  `db.<ref>.supabase.co` host is IPv6-only on the free tier). The backend
  boots and serves `/healthz` cleanly through the pooler.

- **OpenAI key verified.** The first key transcribed from Dave's Note
  was rejected by OpenAI as `invalid_api_key` — the key was three months
  old and either revoked or tied to a deleted project (SHA256 of the
  bytes in `.env` matched what Dave pasted exactly; the key itself just
  wasn't recognized upstream). Dave generated a fresh `sk-proj-…` key;
  `GET https://api.openai.com/v1/models` with it returns `200` and 120
  models, so the key is good and billing is in place.

Still pending for true end-to-end:
- **JWKS auth update** (task #8). Authed endpoints can't validate real
  Supabase Auth tokens until the middleware swaps from HS256/shared-secret
  to JWKS lookup. Until then, every signed-in request returns 401.
- **An actual model call through our backend** — once auth works, hitting
  `/api/kitchen/regenerate-image` or `/api/kitchen/message` will exercise
  the OpenAI client all the way through. That's the last gate on
  "end-to-end verified".
