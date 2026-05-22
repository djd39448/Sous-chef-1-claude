# Backend — Go REST API

Phase 3. Not started.

Rewrites the original Express server (`server/` in sous-chef-ai) in Go. Builds
against [`../contract/`](../contract/) — the API spec, data model, and AI behavior.

Responsibilities:
- All REST endpoints under `/api/` (see `contract/api-spec.md`).
- SSE streaming for chat, recipe generation, and recipe chat.
- Supabase JWT validation middleware.
- Direct OpenAI integration — streaming chat with tool calls, JSON-mode
  generation, `gpt-image-1` image generation.
- Direct PostgreSQL connection to the Supabase database.

Gated on: Go toolchain install, an OpenAI API key.
