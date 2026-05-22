# Backend — Go REST API

Phase 3 of the port. A from-scratch Go rewrite of the original Express server
(`server/` in `sous-chef-ai`), built against [`../contract/`](../contract/) —
the API spec, data model, and AI behavior. The original code is not reused;
its *behavior* is.

## What it does

- Serves every endpoint under `/api/` (see `contract/api-spec.md`) — 25 in all.
- Streams chat, recipe generation, and per-recipe chat over Server-Sent Events.
- Validates Supabase Auth access tokens (HS256) and enforces per-user ownership.
- Talks to OpenAI directly: streaming chat with tool calls, JSON-mode
  generation, and `gpt-image-1` food photography.
- Connects directly to the Supabase PostgreSQL database via `pgx`.

## Layout

```
cmd/server/        main() — config, DB pool, OpenAI client, HTTP server
internal/config/   environment configuration + .env loader
internal/store/    data-access layer over PostgreSQL (pgx); row + CFO models
internal/openai/   minimal OpenAI client (chat stream, JSON mode, images)
internal/auth/     Supabase JWT validation middleware
internal/api/      HTTP routing, handlers, SSE, tool execution, prompts
```

## Configuration

Copy `.env.example` to `.env` and fill it in. Required variables:

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | Supabase PostgreSQL connection string |
| `SUPABASE_JWT_SECRET` | Verifies Supabase Auth access tokens (HS256) |
| `OPENAI_API_KEY` | OpenAI key with billing enabled |
| `PORT` | HTTP listen port (optional; defaults to `8080`) |

In a deployed environment, set real environment variables instead of a file.

## Run

```sh
go build ./...      # compile
go vet ./...        # static checks
go test ./...       # unit tests
go run ./cmd/server # start the API (needs a populated .env)
```

`GET /healthz` is an unauthenticated health probe. Every `/api/` endpoint
requires an `Authorization: Bearer <supabase-jwt>` header.

## Status

Builds, vets, and tests clean. Not yet exercised end-to-end — that needs a live
Supabase database (apply `../supabase/migrations/`) and an OpenAI key.
Deployment to AWS is Phase 5.
