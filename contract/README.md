# The Contract

This directory is the **single source of truth** for the port. The backend and
the iOS app are written independently; the only thing they share is what is
written here. If a behavior is not in the contract, it is not in the app.

The contract was extracted from the original `sous-chef-ai` source by reading
its behavior — `server/routes.ts`, `server/openai.ts`, `server/storage.ts`,
`shared/schema.ts` — not by translating its code.

## Files

| File | Defines |
|---|---|
| [`data-model.md`](data-model.md) | Every table, the Canonical Food Object, JSONB shapes. |
| [`api-spec.md`](api-spec.md) | Every HTTP endpoint — method, auth, request, response, SSE. |
| [`ai-behavior.md`](ai-behavior.md) | System prompts, OpenAI tool schemas, model IDs and params. |

## Rules

1. **The contract changes first.** If a track needs different behavior, edit the
   contract, then both tracks follow. Never let backend and iOS drift.
2. **Shapes are exact.** JSON field names, casing, and types are normative. The
   original uses `snake_case` inside CFO JSONB and mixed casing on row columns —
   both are preserved exactly so neither track has to guess.
3. **Deviations are logged.** Anything that differs from a literal 1:1 port is
   recorded in [`../docs/PORT_PLAN.md`](../docs/PORT_PLAN.md) under "Decisions log"
   (D1–D4) and called out inline here.
