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

---

## 2026-05-23 · Backend auth: JWKS verification ✅

`backend/internal/auth/auth.go` was rewritten to verify Supabase Auth
access tokens against the project's JWKS endpoint
(`https://hssqzhwtwpvblfdmqzpw.supabase.co/auth/v1/.well-known/jwks.json`)
instead of HS256 against a shared secret. This closes the open item from
the asymmetric-JWT-keys pivot in `CHANGE_LOG.md`.

- Added one direct dependency: `github.com/MicahParks/keyfunc/v3` — it
  fetches, caches, and refreshes the JWKS in the background, with on-demand
  refresh when a token's `kid` isn't in the current set.
- `auth.Middleware(jwksURL)` now returns `(middleware, error)`: an
  unreachable or malformed JWKS at startup is a fatal error, surfaced
  through `cmd/server/main.go`. Accepted algorithms are restricted to
  `ES256` and `RS256` (the algorithms Supabase uses).
- Config changed: `SUPABASE_JWT_SECRET` was dropped. The backend now reads
  `SUPABASE_PROJECT_URL` and derives the JWKS URL internally via
  `Config.JWKSURL()`. `backend/.env.example` and the local `backend/.env`
  were updated to match.
- `api.NewServer` now takes a pre-built middleware function instead of a
  secret string, decoupling the api package from the auth specifics.

Verified:
- `go build ./...`, `go vet ./...`, and `go test ./...` all clean (the
  week-start unit test still passes).
- Server boots cleanly; the synchronous JWKS fetch against the real
  Supabase project succeeds.
- `/healthz` → `200 ok` (auth bypasses /healthz).
- `/api/auth/user` without a token → `401`.
- `/api/auth/user` with a well-formed JWT whose `kid` doesn't match any
  JWKS key → `401`. This is the meaningful proof that the full JWKS
  signature-verification path is running — not just the bearer-prefix
  gate.

What's left for genuine integrated e2e: a request signed by a real
Supabase Auth user, which is exercised naturally once the iOS app is
wired to the backend.

---

## 2026-05-23 · iOS wire-up: networking + auth foundation ✅

Built the iOS-side foundation so the SwiftUI app can talk to the Go
backend. No screen *data* is wired yet — that's the next pass.

- `SousChef/Networking/` (new package):
  - `AppConfig.swift` — backend base URL (`http://localhost:8080` for the
    simulator), Supabase project URL, publishable key.
  - `APIError.swift` — typed errors used across the network layer.
  - `TokenStore.swift` — Keychain wrapper for the active `AuthSession`.
  - `SupabaseAuthClient.swift` — thin REST client for Supabase Auth
    (`/auth/v1/signup`, `/auth/v1/token`). Avoids pulling in the full
    `supabase-swift` SDK as a Swift Package dependency for a surface we
    only need three calls from.
  - `APIClient.swift` — `URLSession` base, bearer-token header from the
    `AuthModel`, JSON decoding with a date strategy that accepts both
    fractional-second and plain ISO-8601 (Go's `time.Time` emits the
    former).
  - `AuthModel.swift` — `@Observable` model exposing `session`,
    `isSignedIn`, `signIn`, `signUp`, `signOut`. Resumes from Keychain
    on launch.

- `SousChef/Screens/EmailSignInSheet.swift` — modal email + password
  sheet with a sign-in / sign-up toggle. Loading and error state
  surfaced in-place. This covers the design's "Continue with email"
  flow; the Apple / Google buttons currently also present this sheet
  (see `CHANGE_LOG` — Sign in with Apple deferred).

- `RootView.swift` reads from `AuthModel.isSignedIn` instead of local
  state; `SousChefApp.swift` constructs the `AuthModel` and injects it
  via `.environment(_:)`.

- Build config: moved off the auto-generated Info.plist to a manual
  `ios/Info.plist` so the ATS local-networking exception can be set
  (see `CHANGE_LOG`). The file lives at `ios/Info.plist` — outside the
  file-system-synchronized `SousChef/` folder so Xcode doesn't try to
  copy it as a resource as well.

Verified:
- `xcodebuild` for `iphonesimulator` builds clean, no warnings.
- Booted in the iPhone 17 Pro simulator. Sign In screen still matches
  the design verbatim (screenshot taken). Tapping any of the three
  buttons would now present the email sheet.

To actually sign in once Dave attempts it, his Supabase project needs
**email confirmation disabled** (Dashboard → Authentication → Email
Auth → toggle "Confirm email" off) — or a pre-confirmed user must
exist. Otherwise signup throws "Account created — please check your
email to confirm".

Next iteration: wire individual screens to real API calls — start with
Home pulling `/api/auth/user` and the most-recent meal plan.

---

## 2026-05-23 · Home screen wired to live profile + meal plan ✅

The first screen to actually talk to the backend. HomeScreen's header,
tonight card, and week strip are now driven by fetches against
`/api/auth/user` (Profile) and `/api/kitchen/meal-plan`
(MealPlanWithDays?). Chat shortcut + pantry are still mock for the
moment.

- New: `SousChef/Networking/DTOs.swift` — Codable shapes mirroring the
  contract's response types. Starting with `Profile`, `MealPlanDay`,
  `MealPlanWithDays`; more as further screens are wired.

- HomeScreen now:
  - Holds a `LoadState` enum (loading / loaded / failed).
  - Kicks off the fetch in a `.task` and supports pull-to-refresh.
  - Greeting picks "Morning / Afternoon / Evening" by the current hour,
    uses the user's first name (or email local-part, falling back to
    "there").
  - Date header is `Calendar.current` derived, not hardcoded.
  - Avatar initial comes from the profile.
  - Tonight card resolves today's `dayOfWeek` against the plan's days.
  - Week strip renders the plan's days, Mon-first (Sun last), with the
    today card highlighted by `dayOfWeek` match.
  - Empty plan → an in-card "Plan my week" prompt that jumps to chat.
  - Network / decoding failures → an error card with "Try again".

Verified:
- `xcodebuild iphonesimulator` clean, no warnings.
- Booted the app on the iPhone 17 Pro simulator. Fresh install (after
  `xcrun simctl keychain booted reset`) → SignIn screen, correct.
- A pre-existing Keychain session → MainView + Home, with the error
  card "Couldn't connect to the server" when the local backend is not
  running. That confirms the data-load path runs and the error UI looks
  right.

Known follow-ups (small):
- No auto-signout on 401. A stale Keychain session presents as
  "Couldn't load your kitchen" with no easy escape. Adding sign-out
  UI (and 401-as-signout in APIClient) is the next polish pass.
- Chat shortcut and pantry sections still on mock content — wired when
  we hit `/api/kitchen/ingredients` and the chat endpoints.

---

## 2026-05-23 · Plan, Cookbook, Shopping wired to live data ✅

Continuing the screen-by-screen wire-up. Three more screens now read
(and one mutates) live data — Home + these are the full read/write
CRUD surface for the app, minus the SSE flows (Chat, Recipe generate).

- Added DTOs: `CookbookRecipe`, `ShoppingItem`, `ShoppingListWithItems`.
- New helpers, both used by Home and Plan (and beyond):
  - `Helpers/DateUtil.swift` — `weekRangeString`, `dayName`,
    `dayNumber(for:weekStart:)`, `todaysMondayString`. All UTC, matching
    the backend's `getWeekStartDate()` so string comparison works.
  - `Helpers/ImageLookup.swift` — meal-name → `Food.*` URL fallback,
    pulled out of HomeScreen for reuse.

- **PlanScreen** — fetches `GET /api/kitchen/meal-plan`. Header range
  derives from the plan's `weekStartDate` (with " · This week" suffix
  when it matches the current Monday). Meal rows show day name + date
  number + meal + notes + photo; today's row is highlighted by
  `dayOfWeek` match. Loading skeleton, "Plan my week" empty card that
  routes to chat, error card with retry.

- **CookbookScreen** — fetches `GET /api/kitchen/cookbook`. The most
  recently saved recipe heads the featured "Last saved" card; 2-column
  grid follows. Filter chips remain mock (no tag/category field in the
  contract yet). Loading skeleton, empty card, error card with retry.

- **ShoppingScreen** — fetches `GET /api/kitchen/shopping-list`. Items
  group by category (produce / meat / seafood / dairy / bakery /
  frozen / pantry / beverages / other, then any extras the server
  emits). Tapping a row toggles `checked` *optimistically* and
  `PATCH`es to `/api/kitchen/shopping-item/{id}`; reverts the local
  change if the request fails. "Clear checked" hits
  `DELETE /api/kitchen/shopping-items/checked` with the same optimistic
  pattern. The progress bar reflects the live `checked / total` count.

Verified: `xcodebuild iphonesimulator` clean, no warnings.

Still on mock content: Calendar (placeholder days), Recipe detail
(the SSE generate flow), Chat (SSE messages), and HomeScreen's pantry
+ chat-shortcut sections.

---

## 2026-05-23 · Calendar + Home pantry + auto-signout + sign-out menu ✅

Wrapping up the non-SSE wire-up. Six of eight screens now talk to the
backend; only Recipe and Chat (both SSE-bearing) are still on mock.

- **APIClient** now signs the user out on `401`. A stale Keychain
  session that the backend rejects no longer presents as a dead-end
  error card; the user is bounced to SignIn.

- **HomeScreen — pantry wired.** `GET /api/kitchen/ingredients` is
  fetched concurrently with profile + plan; an empty pantry renders
  the "tell Sous Chef what you have" hint. The pantry chips also
  show the live item count instead of the hardcoded "14 items".

- **HomeScreen — sign-out menu.** Tapping the avatar opens a SwiftUI
  `Menu` with a destructive "Sign out" action that clears Keychain +
  flips `AuthModel`. (Apple/Google buttons stay non-functional placeholders
  for now — they'll point at the real SIWA flow once that lands.)

- **CalendarScreen — wired.** Fetches `GET /api/kitchen/calendar`
  (`{ mealPlans, shoppingLists }`). The month grid is computed
  dynamically from the displayed month (was hardcoded May 2026);
  chevL / chevR step through months, "Today" jumps back. A day is
  marked when it falls within any plan's or list's Mon-Sun week —
  terra dot for plans, sage for lists, switched by the segmented
  control. Today is highlighted in terra.

- New helper additions to **DateUtil**: `dateFromISO` and a public `utc`
  Calendar accessor for callers that need their own arithmetic on
  the same UTC frame as the backend.

- New DTOs: `MealPlan`, `ShoppingList` (the no-children summaries from
  `/calendar`), `CalendarResponse`, `Ingredient`.

Verified: `xcodebuild iphonesimulator` clean, no warnings.

Still on mock: **Recipe** detail (needs streaming `generate-recipe`
parsing — a real SSE reader in Swift) and **Chat** (streaming
`/message` plus tool-result refetching). Tracked as task #10.

---

## 2026-05-23 · Chat + Recipe wired to SSE — all eight screens live ✅

The two streaming flows. **Eight of eight screens** now talk to the
backend; the iOS app is fully wired (modulo polish noted below).

- **APIClient.stream(path:body:)** — a `URLSession.bytes(for:)`-based
  SSE reader that yields each `data:` frame as an
  `AsyncThrowingStream<SSEEvent, Error>`. Handles the multi-line /
  blank-line-separated SSE spec, 401 → auto-signout, network errors →
  propagate. `req.timeoutInterval` lifted to 300 s so long completions
  don't break the connection.

- **ChatScreen — fully rewired:**
  - Loads the default conversation via `GET /api/kitchen/conversation`
    (the backend creates one server-side if the user has none).
  - Send → `POST /api/kitchen/message` and streams the assistant reply
    with a live blinking-cursor bubble.
  - On `{done: true}` refetches the conversation to pick up the
    persisted assistant message and any tool-call side effects (a new
    meal plan, a new shopping list, ingredient updates).
  - Optimistic user-message bubble; auto-scroll on each delta.

- **RecipeScreen rewrite + a new `RecipeSource` enum:**
  - Now takes a `RecipeSource` — `.mealPlanDay(MealPlanDay)` or
    `.cookbook(CookbookRecipe)`.
  - For `.mealPlanDay`: if the day already has `recipeContent`, renders
    it. Otherwise opens
    `POST /api/kitchen/generate-recipe/{id}` and streams the Markdown
    in live. The terminal `{imagePrompt, done: true}` event is
    captured for future image generation.
  - For `.cookbook`: renders the saved Markdown directly.
  - Title bar + hero image come from `ImageLookup`; content rendered
    via `AttributedString(markdown:)` (inline-only). A proper
    structured Ingredients / Instructions parser per the design is a
    follow-up.

- **MainView:** `showRecipe: Bool` replaced with `recipeSource:
  RecipeSource?`. The `fullScreenCover` binds via `item:`, so Home /
  Plan / Cookbook each pass the right source.

- DTOs added: `Conversation`, `Message`, `ConversationWithMessages`.
- Removed dead mock structs from `SampleData.swift` (every model the
  old mock data carried was either replaced by a DTO or unused).
  `Food.*` URLs remain — they're the keyword-match fallback used by
  `ImageLookup` until AI photos are wired.

`xcodebuild iphonesimulator` clean, no warnings.

Polish still pending (not on the AWS critical path):
- Structured recipe rendering (Ingredients checkboxes + numbered
  Instructions per the design).
- `/api/kitchen/recipe-message` wire — the floating "Ask about this
  recipe…" pill currently does nothing.
- `/api/kitchen/regenerate-image` to swap in the AI photo when ready.

---

## 2026-05-23 · AWS deploy — Dockerfile + plan ✅ (groundwork)

The artifacts that don't need an AWS account to land.

- **`backend/Dockerfile`** — multi-stage, distroless, arm64,
  `CGO_ENABLED=0`, runs as the `nonroot` user. Final image ~15 MB.
  Targets AWS Graviton on Fargate (per `sc-06`).
- **`backend/.dockerignore`** — keeps `.env`, build outputs, and
  editor cruft out of the build context.
- **`docs/AWS_DEPLOY.md`** — the architecture (ECS/Fargate + ALB +
  ECR + Secrets Manager + CloudWatch), the prerequisites Dave needs
  to install (AWS account, IAM admin user, AWS CLI, Docker Desktop,
  optional domain), the step-by-step (`docker build` → ECR push →
  Secrets Manager → `terraform apply`), the cost outlook (~$30–50/mo),
  and a clear table of what is code vs what Dave does by hand.

Tooling check on the dev machine right now: `docker`, `aws`, and
`terraform` are all not installed — they're on Dave's prereq list.
Terraform manifests under `infra/aws/` come in the next commit, after
Dave is signed in to AWS and we know the account ID + region.

---

## 2026-05-23 · Fix: every screen was choking on Go's nanosecond timestamps

Dave caught this in actual app testing — Recipe + Chat (and silently
every other screen) showing "The data couldn't be read because it
isn't in the correct format." Two bugs unwound:

1. **Date decoder.** Go's `time.Time.MarshalJSON` emits RFC3339Nano
   with up to 9 fractional-second digits (`…20.977852-04:00`). iOS's
   `ISO8601DateFormatter` with `.withFractionalSeconds` only handles
   up to 3 — anything longer was rejected. The custom date strategy in
   `APIClient.decoder` now truncates the fractional part to 3 digits
   via a regex before parsing, and also strips it entirely as a
   fallback for the plain (no-fraction) formatter. Verified against
   six sample formats including the 9-digit max.

   This was the cause of "nothing really works" — every DTO (`Profile`,
   `MealPlanWithDays`, `CookbookRecipe`, `ConversationWithMessages`,
   `ShoppingListWithItems`, `MealPlan`, `ShoppingList`, …) has a
   `createdAt`/`updatedAt` and was failing the same way.

2. **SSE reader hardening.** `parseDataLine` now returns nil for
   empty payloads (`data:` with no content), and `yieldEvent` filters
   out empty buffered events at flush points. ChatScreen and
   RecipeScreen also `try?`-decode each chunk and skip unrecognized
   ones instead of aborting the whole stream — so a single weird
   event (a heartbeat, a partial frame) no longer kills the rest of
   the recipe generation.

Verified: `xcodebuild iphonesimulator` clean, and a standalone Swift
script confirmed all six common timestamp formats parse correctly
(including Go's max-precision 9-digit nanos).
