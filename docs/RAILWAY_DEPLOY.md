# Sous Chef — Railway Deployment

The Go backend deploys to **Railway**. (We pivoted away from the AWS
Fargate plan documented in `AWS_DEPLOY.md` — see `CHANGE_LOG.md` for
the why. The AWS plan stays in the repo as reference for the future,
not as an active runbook.)

## Architecture

```
   iPhone (anywhere on the internet)
          │
          ▼  HTTPS
   souschef-backend-production.up.railway.app
          │
          ▼
   ┌──────────────────────┐
   │  Railway container   │  Dockerfile → distroless static binary
   │  souschef-backend    │  reads env from Railway variables panel
   └──────────┬───────────┘
              │
              ▼
   ┌──────────────────┐         ┌──────────────────┐
   │  Supabase (DB)   │         │  OpenAI API      │
   │  pooler:5432     │         │  gpt-4.1 + img   │
   └──────────────────┘         └──────────────────┘
```

Railway hosts only the API. The database stays on Supabase (the same
pooler URL the dev backend used). OpenAI stays direct.

## Identifiers

- **Workspace:** `djd39448's Projects` — id
  `1311ac10-f396-4457-8c84-312c16d8e887`
- **Project:** `souschef-backend` — id
  `739e4094-49d6-400f-ad00-6a1a742e38f9`
- **Service:** `souschef-backend` — id
  `67acaf3d-f8fb-4982-bb48-cba7d9aa1c32`
- **Environment:** `production`
- **Public URL:** https://souschef-backend-production.up.railway.app

## Environment variables

Set via `railway variables --set "KEY=VALUE"` (or the dashboard).
Mirrors `backend/.env` minus the empty defaults.

| Variable                | Source                                    |
|-------------------------|-------------------------------------------|
| `DATABASE_URL`          | Supabase pooler connection string         |
| `SUPABASE_PROJECT_URL`  | `https://hssqzhwtwpvblfdmqzpw.supabase.co` |
| `OPENAI_API_KEY`        | `sk-proj-…` (Dave's key)                  |
| `PORT`                  | Provided by Railway automatically         |

The server reads them via `internal/config/config.go`. `PORT` defaults
to `8080` if absent, so local dev still works.

## Build

Railway picks up `backend/Dockerfile`. The Dockerfile is portable
across arches via `$BUILDPLATFORM` + `$TARGETOS`/`$TARGETARCH` (Railway
runs amd64; an Apple-silicon dev box would build arm64). Final image is
distroless static, ~15 MB, runs as `nonroot:nonroot`, no shell.

## Deploy commands

From `backend/`:

```bash
# One-time, already done
railway init --name souschef-backend --workspace <workspace-id>

# Set env vars from the local .env (one-time and on rotation)
set -a; source .env; set +a
railway variables \
  --set "DATABASE_URL=$DATABASE_URL" \
  --set "SUPABASE_PROJECT_URL=$SUPABASE_PROJECT_URL" \
  --set "OPENAI_API_KEY=$OPENAI_API_KEY"

# Deploy
railway up --detach

# After the first deploy, the service exists — link it:
railway service souschef-backend

# Generate / inspect the public URL
railway domain

# Tail logs
railway logs
```

`railway up` re-deploys the current working tree. Railway also auto-
deploys on Git pushes if the GitHub integration is hooked up — not
configured today (we deploy from the local CLI).

## Verifying

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  https://souschef-backend-production.up.railway.app/healthz
# → 200
```

Then sign in on the iOS app — every screen pulls from the Railway
backend; the LAN-IP dev backend is no longer the source of truth.

## Rolling back

```bash
railway status --json | jq '.environments.edges[].node.serviceInstances.edges[].node.latestDeployment.id'
# → last deploy id
railway redeploy <previous-deploy-id>
```

Or via the dashboard at the project's Deployments tab.

## What we did NOT set up (yet)

- **Custom domain.** The auto-generated `*.up.railway.app` URL works;
  custom domain is a `railway domain <hostname>` away.
- **Auto-deploy on git push.** Manual `railway up` for now — switch in
  the dashboard if/when this stops feeling fast enough.
- **Migrations on deploy.** The `cmd/migrate` tool is run manually
  against Supabase from a dev machine. The original Aurelion deploy
  did this in a pre-deploy step; can copy that pattern later.

## See also

- `AWS_DEPLOY.md` — the pre-pivot AWS Fargate plan, kept for reference.
- `CHANGE_LOG.md` — pivot entry explaining the AWS→Railway move.
- `backend/Dockerfile` — the image Railway builds.
