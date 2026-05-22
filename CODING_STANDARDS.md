# Sous Chef — Coding Standard

**Version:** 1.0
**Status:** Active
**Date:** 2026-05-22
**Applies to:** this repository — the contract, the Supabase schema, the Go
backend, and the SwiftUI iOS app.

These standards are non-negotiable. Every module, every commit, every test,
every migration must follow them — whether written by a human or by Claude.

---

## sc-00 — Intent: The codebase stands on its own

> "The goal is to be able to give this to another dev and say no words. The dev
> will know exactly what they are looking at without guessing. The code base
> needs to stand by itself. It should be the default mode."

This is the governing principle. A developer handed this codebase — with zero
verbal explanation and zero prior context — must be able to answer, **from the
code alone**, what every part is, what it does, why it exists, how it connects,
and how to change it safely.

No tribal knowledge. No onboarding call. No "ask the person who built it." The
code, its annotations, the contract, the migrations, the logs, and the commit
history ARE the documentation. If a reader has to guess, the code failed this
standard.

This is not a final polish step. It is the **default mode of writing** — every
file, every commit, from the first line.

---

## sc-01 — Scope, layout, and the file-header rule

### The stack

| Layer | Technology |
|---|---|
| Behavior contract | Markdown under `contract/` — single source of truth |
| Database | Supabase / PostgreSQL — `supabase/migrations/*.sql` |
| Backend API | Go (`backend/`, module `souschef`) |
| iOS app | Swift / SwiftUI (`ios/SousChef.xcodeproj`) |
| Backend hosting (target) | AWS (Phase 5) |

Three build tracks — backend, data, iOS — each build independently against the
one shared contract. **Change the contract first**; both tracks follow.

### Repository layout

```
/                    governance — README, CLAUDE, standards, logs
contract/            the API spec, data model, AI behavior — source of truth
supabase/migrations/ versioned SQL migrations + RLS policies
backend/             Go REST API
  cmd/server/        the API binary
  cmd/migrate/       a one-shot SQL migration runner
  internal/          all non-public code
ios/                 SwiftUI app
  SousChef.xcodeproj
  SousChef/          source — file-system-synchronized target
docs/                the live PORT_PLAN
```

### The file-header rule

Every file states what it does, what it depends on, what depends on it, and why
it exists. The syntax changes per language; the requirement does not.

```go
// Package store is the data-access layer over the Supabase PostgreSQL
// database. It connects directly with a service-role-level credential and
// bypasses row-level security; per-user ownership is enforced by the API
// layer, faithful to the original Express server.
package store
```

```swift
//  Theme.swift
//
//  Sous Chef design tokens — the SwiftUI port of `T` in shared.jsx.
//
//  Depends on:     SwiftUI, Foundation (math for the OKLCH conversion).
//  Depended on by: every screen and component (colors, fonts).
//  Why it exists:  one place that owns the palette, fonts, and the
//                  OKLCH→sRGB conversion — change tokens here and every
//                  surface follows.
```

```sql
-- Migration: food_items — the Canonical Food Object.
--
-- Depends on:     auth.users (user_id foreign key).
-- Depended on by: meal_plans, shopping_lists (link to items by id).
-- Why it exists:  one table backs the inventory, shopping, planned, and
--                 ingredient roles, so food data is never duplicated.
```

A missing or stale header is a defect — fix it in the same commit you touched
the file.

---

## sc-02 — General code quality

These cross-cutting rules apply in every language and every layer.

- **No silent failures.** Every error is handled, returned, or surfaced. An
  ignored error needs an inline comment explaining why discarding is correct.
- **No dark code.** Dead code, commented-out blocks, "kept for reference"
  scaffolding — all deleted. Git remembers what was removed.
- **Small, reviewable commits.** One concern per commit. The message says what
  changed and *why* — never "wip" or "fixes."
- **Test what's testable, prove what's stateless.** Pure helpers (week-start,
  parsers, prompt builders) carry unit tests. The rest is proven by the
  contract round-trip in Phase 5.
- **CLI for everything.** Anything that builds, deploys, migrates, or boots a
  service does so from a documented command — no GUI-only steps. If a hand
  step is unavoidable (App Store Xcode install, Apple Developer onboarding),
  it is documented in this standard or the project README.

---

## sc-03 — Go

Baseline: **Go 1.26**. Pin in `go.mod` (`go 1.26.0`).

### Project layout
- `cmd/<binary>/main.go` per executable. `main` does only wiring — config,
  pool setup, signal handling — then delegates. *Entrypoints stay thin.*
- `internal/` holds all non-public code. The compiler import-walls it.
- One module per repo (`backend/go.mod`).
- Package name = directory name: lowercase, no underscores, no plurals.
  Packages reflect behavior, not layers. **No `utils`, `helpers`, `common`,
  or `models` packages** — they reveal nothing at the call site.

### Error handling
- Errors are values: handle them or return them, **never ignore them**. An
  explicit `_ =` requires an inline comment.
- Wrap with `fmt.Errorf("doing X: %w", err)` to preserve the chain. Branch
  with `errors.Is` (sentinels) and `errors.As` (typed errors).
- Sentinel errors (`var ErrNotFound = errors.New(...)`) for simple
  conditions; typed errors when callers need structured fields.
- Error strings are lowercase, no trailing punctuation, no `"failed to"`
  prefix — they get nested. Each layer wraps with what it was doing.
- `panic` only for unrecoverable invariant violations — never for control
  flow or expected failure. `recover` only at a process boundary.

### context.Context
- Any function that does I/O, blocks, or crosses goroutines takes
  `ctx context.Context` as its first parameter. Propagate the received `ctx`
  — never re-root with `context.Background()` mid-chain.
- Pass `ctx` into every DB and HTTP call; `select` on `ctx.Done()` in loops.
- A context carries request-scoped transit data only (request ID, trace
  span, auth principal). **Never** put config, loggers, or optional
  parameters in a context — that hides the real API.

### REST handlers
- A handler does four things: decode → validate → call a store/openai
  method → encode. **No business logic in handlers.** Dependencies live on
  a `Server` struct; routes are registered in one place.
- Validate input at the boundary. Client JSON is untrusted past the handler.
- One consistent error envelope (`{"error":"..."}`). Internal error detail
  is logged, never returned to the client.
- `http.ServeMux` method+path patterns (`"POST /api/kitchen/message"`) are
  sufficient — add a third-party router only with a stated reason.

### Streaming (SSE)
- SSE endpoints (`/api/kitchen/message`, `generate-recipe`, `recipe-message`)
  do all pre-flight validation *before* writing the SSE headers, since a
  written `200 text/event-stream` cannot be revoked.
- Errors **before** the stream → plain JSON `4xx`/`5xx`. Errors **after**
  the stream starts → `data: {"error":"..."}` event, then end the stream.
- Every SSE event is `data: <json>\n\n` and is flushed before the next line.

### Concurrency
- Every goroutine has a defined exit condition, and the code starting it
  knows how and when it stops. *An unbounded goroutine is a memory leak.*
- Channels transfer ownership and signal; mutexes protect shared state. Do
  not mix paradigms for one piece of state.
- CI runs `go test -race ./...`. Data races are undefined behavior; the
  detector is the only reliable catch.

### Testing
- Table-driven tests, subtests via `t.Run`. `t.Parallel()` unless shared
  state forbids it.
- Tests live in `_test.go` beside the code. Black-box (`package <name>_test`)
  by default — test the public API.
- Default to the stdlib `testing` package. `testify/assert` is permitted to
  cut assertion noise; **heavy mock frameworks are not** — hand-write fakes
  against narrow consumer interfaces.

### Logging
- `log/slog` exclusively in service code. No `fmt.Println` past the
  prototype phase. Structured key/value attributes — never format data into
  the message string.

### Dependencies
- Minimal. Every direct dependency needs a justification; prefer the stdlib
  and `golang.org/x/*`. *Each dependency is supply-chain surface.*
- `go mod tidy` on every change; commit `go.mod` and `go.sum`. No `replace`
  directives in mainline.
- The current direct dependencies are `github.com/jackc/pgx/v5` (Postgres)
  and `github.com/golang-jwt/jwt/v5` (Supabase JWT validation). Adding a
  third needs a CHANGE_LOG entry.

### Tooling
- `gofmt`/`gofumpt` clean; CI fails on any diff.
- `go vet ./...` and `go test ./...` clean on every commit.

---

## sc-04 — Swift / SwiftUI

Baseline: **Swift 5+**, Xcode 26+, iOS 17+ deployment target.

### Architecture
- Plain **Model–View**. Do not add a `ViewModel` per screen — SwiftUI's
  `@Observable` macro lets views observe models directly at property
  granularity, so a pass-through ViewModel layer adds no value.
- Business logic lives in plain types and service objects, **never in a
  `View` struct**. A `View` is a declarative description of UI for given
  state — layout, bindings, event forwarding, nothing else.
- A model or service type **never** `import SwiftUI`. *Keeps logic
  UI-independent and testable.*

### State
- `@State` for view-local state the view owns; `@Binding` for state owned
  elsewhere; `@Environment` for app-wide dependencies.
- Shared state: `@Observable` classes (the macro). **Do not use
  `ObservableObject`, `@Published`, `@StateObject`, or `@EnvironmentObject`
  in new code** — they invalidate every observer on any change.
- One owner per piece of state.

### Concurrency
- `async`/`await` for all asynchronous work. No `DispatchQueue` or
  completion handlers in new code.
- Off-main work is deliberate and visible — opt in with `Task.detached`
  or an explicit `actor`. Most app code is UI code and belongs on the
  main actor.
- Every `Task` is tied to a lifecycle — prefer `.task { }` on views (it
  auto-cancels on disappear).

### Error handling
- `throws` with `do`/`catch`. Convert errors explicitly at layer boundaries
  — a low-level networking error never leaks straight into UI code.
- User-facing errors surface in the UI via a `LocalizedError`-conforming
  type. Never swallow an error to show an empty screen.

### Views
- A `body` fits on screen without scrolling. Break large bodies into
  computed `private var xxx: some View` properties — and once a body has
  multiple sub-sections, prefer extracted helper views.
- Pass a subview the minimum data it needs, not a whole model.
- Repeated styling becomes a `ViewModifier` or a small reusable view.

### Networking
- **All** HTTP access goes through a single `APIClient` backed by
  `URLSession`. No `URLSession` calls scattered in views or models.
- Use `async` methods (`data(for:)`); validate the `HTTPURLResponse` status
  and throw a typed error on non-2xx.
- Wire DTOs (matching the API contract) are separate from domain models.

### Project layout
- Group by feature or screen, not by type. The current iOS layout (`Screens/`,
  `Components.swift`, `Theme.swift`, `SampleData.swift`, `RootView.swift`,
  `SousChefApp.swift`) is the baseline; grow by adding peer files.
- One primary type per file; filename equals the type name.

### Design system
- Colors live in `Theme.swift`, authored as `oklch(...)` to match the
  prototype's `shared.jsx`. The OKLCH→sRGB conversion happens once in
  `Color.init(oklch:_:_)` — change a token there and every surface follows.
- Display font: `Theme.display(_:weight:)`. Body font:
  `Theme.sans(_:weight:)`. Swapping in Fraunces later is a one-function
  change here plus dropping in the font files.
- Icons: SF Symbols via `SCIcon` — add a case to the mapping when a new
  glyph is needed.

### Testing
- Use the **Swift Testing** framework (`@Test`, `#expect`) for new tests.
- Test pure logic (week-start helpers, parsers, model transforms). Views
  ship `#Preview`s for key states.

### Accessibility
- Meaningful labels on every interactive element. Decorative images hidden
  from assistive tech. Dynamic Type supported (no fixed font sizes).
  Reduce Motion respected. Contrast minimums met.

---

## sc-05 — Supabase / PostgreSQL

Baseline: Supabase on PostgreSQL 15+.

### Schema design
- `snake_case` everywhere. Tables are plural nouns (`meal_plans`), columns
  singular.
- Every table has `created_at timestamptz NOT NULL DEFAULT now()` and an
  `updated_at timestamptz NOT NULL DEFAULT now()` maintained by trigger
  (`set_updated_at`).
- Use the narrowest correct type: `text` (never `varchar(n)`), `numeric`
  for money, `boolean` for flags. **One historical exception is preserved
  for fidelity:** `shopping_list_items.checked` is `integer` (0/1) — see
  CHANGE_LOG D3.
- JSONB **only** for genuinely schemaless data — the CFO blobs in
  `food_items` are the canonical example.

### Constraints — enforce in the database
- `NOT NULL` is the default; every nullable column is justified.
- Declare every foreign key explicitly with an `ON DELETE` action chosen
  deliberately (`CASCADE`, `RESTRICT`, `SET NULL`).
- Expression unique indexes when the identity invariant is composite —
  `food_items` is keyed on `(user_id, canonical_name, usage_context->>'role')`.

### Row-Level Security
- RLS is **default-on** for every table in `public`. Enable it the moment
  the table is created — a forgotten table in an exposed schema is a public
  data leak.
- Write one policy per operation; scope the role explicitly
  (`TO authenticated` / `TO anon`).
- Index every column a policy references.
- The Go backend connects with a service-role credential that **bypasses
  RLS** and enforces ownership in code — faithful to the original Express
  server (see CHANGE_LOG: ownership is uniform 403/404 across `:id`
  endpoints). RLS policies are defense-in-depth for the PostgREST surface
  the iOS app may use directly.

### Auth
- Supabase Auth, never a hand-rolled identity layer. Sign in with Apple uses
  the native iOS flow (`signInWithIdToken`).
- The publishable (anon) key is the **only** Supabase key shipped to the
  iOS app. The service-role key never reaches a client, a repo, or an app
  bundle.

### Migrations
- All schema changes are SQL migrations in `supabase/migrations/`, applied
  via the Go `cmd/migrate` runner (or the Supabase CLI when available).
- **Never edit an applied migration** — add a new one. Editing breaks every
  environment that already ran it.
- Migrations are small, single-purpose, and reviewed like any other code.

### Performance
- Index every foreign key (Postgres does not do this automatically) and
  every RLS policy column. Always paginate. `EXPLAIN ANALYZE` policy-bearing
  queries before merge — a seq scan on a large table is a defect.

---

## sc-06 — AWS Deployment (Phase 5 target)

The Go backend will deploy to AWS. These rules apply when that lands.

- **Compute by traffic shape.** ECS/Fargate is the default for a
  steady-traffic REST API. Lambda for event-driven / spiky low volume.
- **Build.** Multi-stage Docker from `scratch` or a distroless base,
  `CGO_ENABLED=0`, static binary, Linux target (`GOOS=linux GOARCH=arm64`
  for Graviton). Tag images immutably by git SHA.
- **Config.** All configuration via environment variables (twelve-factor).
  No config files baked into images.
- **Secrets.** AWS Secrets Manager or SSM Parameter Store, fetched at
  startup. `DATABASE_URL`, `SUPABASE_JWT_SECRET`, `OPENAI_API_KEY` are
  secrets — never in env vars committed to IaC, never in the image, never
  in the repo.
- **Observability.** `slog` JSON to stdout → CloudWatch Logs. `/healthz`
  endpoint for the load balancer (already implemented, unauthenticated).
- **Infrastructure is code.** The cluster, service, and networking are
  Terraform or CDK — no console click-ops for anything that must be
  reproducible. IAM roles follow least privilege.

---

## sc-07 — The Contract

The contract under `contract/` is the single source of truth for behavior.
The backend and the iOS app are written independently; the only thing they
share is what is written there. If a behavior is not in the contract, it is
not in the app.

- **The contract changes first.** If a track needs different behavior, edit
  the contract, then both tracks follow. Never let backend and iOS drift.
- **Shapes are exact.** JSON field names, casing, and types are normative.
  Row columns are `camelCase` in the API; CFO JSONB blobs stay `snake_case`
  — both are preserved exactly so neither track has to guess.
- **Deviations from a literal 1:1 port are logged** in
  [`docs/PORT_PLAN.md`](docs/PORT_PLAN.md) under "Decisions log" (D1–Dn)
  *and* in `CHANGE_LOG.md`. The two stay in sync.
- **AI prompts are reproduced verbatim** (see `contract/ai-behavior.md`).
  Do not "improve" them during the port.
- **Backend-internal details that the iOS track does not see** — exact
  prompt strings, fallback lists, internal logging — live in the backend
  and are *documented* in `contract/ai-behavior.md` for fidelity, but the
  contract for the iOS track is `api-spec.md` + `data-model.md`.

---

## sc-08 — macOS / Xcode environment

This project is developed on macOS Apple Silicon (M4 Mac Mini). Common
environment gotchas — each lists the **symptom**, the **cause**, and the
**fix**.

### Case-insensitive filesystem
- **Symptom:** a file renamed only by case is not picked up; two files
  differing only in case collide; imports behave strangely.
- **Cause:** APFS on macOS is case-insensitive by default.
- **Fix:** never rely on case to distinguish files or identifiers. CI on
  case-sensitive Linux *will* fail on a mismatch.

### Cross-compiling Go for AWS
- **Symptom:** a binary built on the Mac does not run on AWS.
- **Cause:** the Mac is arm64/Darwin; the AWS target is Linux.
- **Fix:** `GOOS=linux GOARCH=arm64 CGO_ENABLED=0` in CI, never by hand.
  Local `go build` is for local runs only.

### Xcode and macOS version coupling
- **Symptom:** the App Store refuses to install the latest Xcode.
- **Cause:** each Xcode major needs a matching macOS major (Xcode 26 needs
  macOS 26 Tahoe).
- **Fix:** upgrade macOS via Software Update before installing Xcode. If
  staying on an older macOS is required, install an older Xcode (matching
  major) via the `xcodes` CLI from `developer.apple.com`.

### Stale Command Line Tools
- **Symptom:** `brew install <anything>` errors with "Your Command Line
  Tools are too outdated."
- **Cause:** the standalone CLT at `/Library/Developer/CommandLineTools` is
  from before the macOS upgrade.
- **Fix:** `sudo rm -rf /Library/Developer/CommandLineTools && sudo
  xcode-select --install`. (Not needed for Go or Xcode itself — Go uses its
  own toolchain, and Xcode brings everything it needs.)

### Xcode code signing and device runs
- **Symptom:** the app runs in the simulator but won't install on a phone.
- **Cause:** device installs require a provisioning profile and an Apple
  Developer account; the simulator does not.
- **Fix:** document the signing setup (team ID, bundle ID, profile) in
  `ios/README.md` when device builds begin. Never commit certificates or
  `.p8` keys.

### macOS filesystem cruft
- **Symptom:** `.DS_Store` or `xcuserdata` files appear in commits.
- **Cause:** Finder and Xcode write them into directories automatically.
- **Fix:** `.DS_Store`, `*.xcuserdata`, and `ios/build/` are in
  `.gitignore` from the first commit.

### Local secrets
- **Symptom:** an API key (Supabase service role, OpenAI key, Apple `.p8`)
  lands in the repo.
- **Cause:** secrets kept in a tracked file for convenience.
- **Fix:** local secrets live in `backend/.env` (gitignored) or the macOS
  Keychain — never a tracked file. `backend/.env.example` documents what is
  required without leaking anything.

---

## sc-09 — Pre-commit checklist

Before any commit lands on `main`:

```
[ ] Every new/touched file carries the sc-01 header (what / depends on /
    depended on by / why)
[ ] No silent failures, no dropped errors, no commented-out dead code
[ ] Go:    gofmt clean, go vet clean, go test ./... passes
[ ] Go:    errors wrapped with %w; ctx propagated, never re-rooted
[ ] Swift: xcodebuild builds clean for iphonesimulator (no warnings)
[ ] Swift: new tests use Swift Testing; views carry #Preview for key states
[ ] SQL:   any new migration is additive (no edits to applied migrations),
           small, single-purpose; RLS enabled on every new public table
[ ] The contract is updated FIRST when behavior changes; backend and iOS
    follow. Deviations recorded in PORT_PLAN and CHANGE_LOG.
[ ] Secrets: no key, token, or service-role credential anywhere in the diff
[ ] BUILD_LOG entry added when a phase/work session completes; CHANGE_LOG
    entry added when direction changes
```
