# Sous Chef — Change Log

This log records **decisions and changes of direction** for the Sous Chef
port. When the project pivots — a chosen path turns out wrong, a workaround
replaces the intended approach, a contract is clarified — the change is
recorded here as an explicit entry. The docs are never silently updated to
make a new direction look like it was always the plan.

**Scope:** changes to *this project* — its contract, its architecture, its
process. Implementation-level bug fixes belong in commit messages, not here.

**Format:** newest first. Each entry: date, what changed, why.

---

## 2026-05-27 — Week dates: UTC → user-local

**Changed:** `weekStartDate` is now anchored to the iOS client's
`Calendar.current` (the user's local Monday), not UTC. The iOS app passes
the local Monday string to every endpoint that takes a week — including
the new optional `weekStartDate` fields on `POST /api/kitchen/message`
and `POST /api/kitchen/generate-shopping-list`. The backend's
`currentWeekStart()` (UTC) becomes a fallback used only when the client
omits the value. Contract updated: `api-spec.md` (new Week-anchoring
convention + body fields on message / generate-shopping-list);
`ai-behavior.md` (week-start helper now notes the local-anchoring rule).

**Why:** the port had three definitions of "today" coexisting —
HomeScreen and PlanScreen derived today's day-of-week from
`Calendar.current` (local), while `DateUtil.todaysMondayString()`,
CalendarScreen's month grid, and the backend's `currentWeekStart()` all
used UTC. On Sunday evenings in EDT (when UTC has already rolled to
Monday) PlanScreen would load *next* week's plan while HomeScreen still
showed Sunday's meal as tonight's dinner. The calendar grid would
highlight Monday while the rest of the app insisted today was still
Sunday. Anchoring everything to the user's perceived calendar is the
only fix that survives DST transitions and time-zone changes
gracefully; the backend's UTC `currentWeekStart()` survives as a safe
fallback for server-initiated work.

---

## 2026-05-24 — Deploy target: AWS Fargate → Railway

**Changed:** Switched the backend deployment plan from AWS ECS/Fargate
(per `docs/AWS_DEPLOY.md`) to **Railway**. The backend now lives at
`https://souschef-backend-production.up.railway.app` and the iOS app
points there instead of the dev Mac mini's LAN IP. The
backend `Dockerfile` was generalized from arm64-only (Graviton) to
multi-arch via `$BUILDPLATFORM` / `$TARGETARCH`.

**Why:** Railway gets the API onto the public internet in one
`railway up` from the `backend/` directory. The AWS plan required
Terraform manifests, ECR auth, ALB + ACM cert provisioning, IAM roles,
and Secrets Manager wiring — meaningful learning for Dave's other
project but heavy for a single Go service. Dave already has a Railway
account and the AURELION API is hosted there, so the workflow is
familiar.

`docs/AWS_DEPLOY.md` stays in the repo as a reference for the future
(useful for the `DevCore` project that does need AWS surface). The
authoritative runbook for the current backend is now
`docs/RAILWAY_DEPLOY.md`.

---

## 2026-05-23 — Contract: added `save_recipe` as the fourth main-chat tool

**Changed:** The contract (`contract/ai-behavior.md`) now lists **four**
function tools for the main chat instead of three. The new one is
`save_recipe` — the model can persist the recipe it just generated to
`cookbook_recipes` when the user asks to save.

**Why:** the port pulled the tool list verbatim from the Replit web app,
which never had a save-recipe tool. The chat handles "save this" by
having the model write a confirmation reply ("Got it! I've saved…"),
but nothing actually persists. Real-device testing surfaced the gap
immediately: the chat lies about saving, then the Cookbook tab shows
empty. Adding a real tool is a strict expansion of behavior — no
existing flow changes — so it goes into the contract rather than
sitting in a backend-only patch.

The `POST /api/kitchen/cookbook` route already existed and worked; the
only thing missing was an in-chat caller for it. Adding the tool also
lets the model write its own image prompt for the saved recipe (the
schema accepts an optional `imagePrompt`), which lines up with how
meal-plan recipe generation already emits one.

---

## 2026-05-23 — Sign in with Apple deferred; email auth is the dev path

**Changed:** Decision D1 set Sign in with Apple as the primary sign-in
path. For now, the design's three sign-in buttons (Apple, Google, email)
all present an email + password sheet that talks to Supabase Auth via
REST. The SIWA wiring is queued.
**Why:** Sign in with Apple requires (a) an Apple Developer Program
enrollment ($99/yr; ~24-48hr provisioning) and (b) the Supabase Apple
provider configured with a service id, team id, key id, and a `.p8`
key. Neither is in place yet, and we'd rather have the rest of the app
working end-to-end first. When SIWA lands the `EmailSignInSheet`
remains as the fallback.

## 2026-05-23 — Manual Info.plist for ATS local-networking exception

**Changed:** the iOS app now ships a manual `ios/Info.plist`
(`INFOPLIST_FILE = Info.plist`) instead of relying on
`GENERATE_INFOPLIST_FILE`.
**Why:** the iOS Simulator needs an `NSAppTransportSecurity →
NSAllowsLocalNetworking` exception to make plain-HTTP requests to
`http://localhost:8080` during dev. ATS sub-keys aren't settable via
the `INFOPLIST_KEY_*` build settings, so a manual Info.plist is the
straightforward fix. The file lives at `ios/Info.plist` — outside the
file-system-synchronized `SousChef/` folder so Xcode doesn't also try
to copy it as a bundle resource.

## 2026-05-22 — Supabase project uses asymmetric JWT signing keys

**Changed:** the Sous Chef Supabase project was provisioned with Supabase's
new asymmetric JWT signing-key format — its API keys are
`sb_publishable_…` and `sb_secret_…`, and Auth-issued JWTs are signed with
an asymmetric key pair (ES256 or RS256). The backend's auth middleware
(`backend/internal/auth/auth.go`) currently verifies HS256 against a
shared `SUPABASE_JWT_SECRET`, which does not work against asymmetric tokens.
**Why:** new Supabase projects default to the new format; the legacy
HS256 shared secret is being deprecated. The forward-compatible fix is to
verify via the project's JWKS endpoint
(`https://<ref>.supabase.co/auth/v1/.well-known/jwks.json`) — fetch the
keys, cache them, look up by `kid` from the token header, verify with the
public key. `backend/.env` carries a placeholder `SUPABASE_JWT_SECRET` so
the server boots and `/healthz` works; the JWKS update is the next backend
change (tracked as a task).

## 2026-05-22 — Phase 4 typeface: Fraunces → system serif

**Changed:** the design prototype calls for Fraunces (a Google variable font)
as the display face on every screen title. The SwiftUI port uses the **system
serif** (New York, `Font.system(_:weight:design:.serif)`) instead.
**Why:** bundling a variable font correctly (Info.plist registration, exact
PostScript names, optical-size handling) without a way to visually verify each
step is a real risk for a non-rendering result. The system serif is native,
Dynamic-Type aware, and renders correctly out of the box. `Theme.display(_:)`
is the single function to change later; dropping in Fraunces is a one-call
swap plus adding the font files.

## 2026-05-22 — Phase 4 design source: a Claude Design handoff bundle

**Changed:** the original PORT_PLAN sketched the iOS UI in general terms
("Figma wireframes will define the native look"). Phase 4 was built against a
specific Claude Design handoff bundle that arrived during this session —
`api.anthropic.com/v1/design/h/KhpIMpXa_P34Sx-Oo9-eMA` — an HTML/React
prototype of all 8 screens with a complete design system (`shared.jsx`).
**Why:** a concrete pixel-faithful design exists, with the design system,
colors (OKLCH), components, and screens already worked out. Implementing
against the prototype is faster, more consistent, and less error-prone than
inventing the visual layer from a written brief.

## 2026-05-22 — Backend end-to-end verification deferred to do Phase 4 first

**Changed:** after Phase 3 the chosen next step was "set up Supabase + OpenAI,
verify the backend end-to-end, then build Phase 4." That order was reversed
mid-session: Phase 4 was built first, with backend verification still pending.
**Why:** the user opted to set Supabase aside for the moment. The iOS app
builds against the contract (not the live backend), so Phase 4 was
unblocked. Backend verification remains the next step before Phase 5.

## 2026-05-22 — Supabase CLI install dropped; cmd/migrate built instead

**Changed:** PORT_PLAN listed the Supabase CLI as a prerequisite for applying
schema migrations. The CLI is not used; instead, a tiny Go runner —
`backend/cmd/migrate` — applies the SQL files via `pgx`.
**Why:** `brew install supabase/tap/supabase` is gated by Homebrew on
up-to-date Command Line Tools, which the post-macOS-upgrade machine does not
have. Rather than chase the CLT install (which requires `sudo` and a separate
download), a one-file Go tool that uses the dependency the backend already
has solves the problem with zero extra friction. Adding the CLI later remains
an option; it is no longer on the critical path.

## 2026-05-22 — Phase 3 contract clarification: cookbookContext format

**Changed:** the meal-plan-generation system prompt in `contract/ai-behavior.md`
includes a `<cookbookContext>` placeholder; the contract said only "Build
`cookbookContext` from up to 20 cookbook titles." but did not specify the
format. The backend implements it as
`"The user has these saved recipes they may enjoy — feel free to include some:
<title>, <title>, ...."` (empty string when the user has no saved recipes);
the contract was updated to document exactly that.
**Why:** the contract claims to be the source of truth, and a backend-internal
prompt detail that affects model output should be documented there, not
inferred from the implementation.

## 2026-05-22 — Phase 3 contract clarification: ownership errors unified

**Changed:** `contract/api-spec.md` had two conflicting rules. The general
section said "`403` if the row belongs to another user, `404` if it does not
exist" for any `:id` endpoint; the `GET /api/kitchen/conversation/:id`
sub-section said "`404` if not found or not owned." The general rule wins;
the conversation/:id sub-section was rewritten to match.
**Why:** internal contradiction in a "source of truth" doc is a defect. The
general rule (existence-revealing 403 for not-owned, 404 for missing) was
applied uniformly across every `:id` endpoint in the Go backend; the contract
now reads the same way.

## 2026-05-22 — macOS upgraded to Tahoe 26.5 to unblock Xcode

**Changed:** the dev machine was upgraded from macOS 15.5 (Sequoia) to
macOS 26.5 (Tahoe).
**Why:** the App Store Xcode (the only path to a current Xcode + iOS
Simulator) refused to install on macOS 15.5 with "macOS version 26.2 or later
is required." Staying on Sequoia would have forced an older Xcode 16
installed via `xcodes` from `developer.apple.com`. Upgrading the OS is the
supported path, keeps tooling current, and the M4 Mac mini fully supports
Tahoe.

---

The decisions below were made when the contract was authored. They are the
foundation the port stands on.

## 2026-05-22 — D4: OpenAI called directly; Replit AI proxy dropped

**Changed:** the original `sous-chef-ai` calls OpenAI through Replit's AI
Integrations proxy (`AI_INTEGRATIONS_OPENAI_*`). The port calls OpenAI
directly with Dave's own API key. Model IDs and prompts are preserved as-is.
**Why:** Replit Auth and the Replit AI proxy are the parts that forced the
re-platform in the first place — they don't exist outside Replit. A direct
key has no proxy in the loop and works in any deployment.

## 2026-05-22 — D3: CFO consolidation deferred

**Changed:** the original keeps legacy `ingredient_memory` and
`shopping_list_items` tables and dual-writes them alongside the Canonical
Food Object (`food_items`). The port preserves that behavior faithfully
rather than collapsing the legacy tables into CFO projections.
**Why:** the CFO spec intends lists to be *views* over `food_items`, and
consolidation is a worthwhile future cleanup, but it changes the `checked`
state and free-text quantity handling — that is a refactor, not a
translation, and a port should not silently rewrite behavior.

## 2026-05-22 — D2: Dead chat tables removed

**Changed:** `shared/models/chat.ts` in the original defines `conversations`
and `messages` tables that no route or storage method touches — the live chat
uses `kitchen_conversations` / `kitchen_messages`. The dead pair is not
carried into the new schema.
**Why:** porting unused tables would mislead the next developer reading the
schema. Git history preserves what was removed if it's ever needed.

## 2026-05-22 — D1: Replit Auth → Supabase Auth with Sign in with Apple

**Changed:** Replit Auth (OIDC + Passport) is replaced by Supabase Auth with
Sign in with Apple. The `sessions` table is dropped (Supabase issues JWTs;
no server-side session store needed). The `users` table becomes
`public.profiles`, keyed to `auth.users.id`. Every other table's `user_id`
column becomes a `uuid` referencing `auth.users(id) on delete cascade`.
**Why:** Replit Auth is Replit-specific and doesn't exist outside their
platform. iPhone users expect Sign in with Apple. Supabase Auth provides it
natively, and standardizing on `uuid` user IDs simplifies every relationship.

## 2026-05-22 — Method: port behavior, not code; three tracks on one contract

**Decided:** the port is a clean re-platform — every layer rewritten natively
(SwiftUI iOS, Go backend, Supabase data). Almost zero line-level code reuse.
What carries over is the *contract* — the API surface and the CFO data
model.
**Why:** the original is React + Express + Replit-specific glue. Translating
code line-for-line locks the port into the original's accidents
(Replit-isms, framework-specific patterns) and yields a worse result than a
native rebuild. The contract is small; native code at each layer is better
than translated code.

## 2026-05-22 — First workload: port `sous-chef-ai` to a native iOS app

**Decided:** the user wants `sous-chef-ai` running on his iPhone. Building
the port is the work.
**Why:** the original is a mobile-first web app — useful, but not native.
Native iOS gives Sign in with Apple, real food photography, system fonts,
proper safe-area handling, and a path to the App Store.
