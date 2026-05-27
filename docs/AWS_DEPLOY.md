# Sous Chef — AWS Deployment Plan (SUPERSEDED)

> **⚠️ Superseded 2026-05-24.** The backend is deployed to **Railway**,
> not AWS. See [`RAILWAY_DEPLOY.md`](RAILWAY_DEPLOY.md) for the
> authoritative runbook and `CHANGE_LOG.md` (2026-05-24 entry) for the
> pivot rationale. This file is kept as a reference if/when the backend
> moves to AWS later, or to inform other projects (e.g. DevCore) that
> need the AWS surface.

The Go backend deploys to AWS. This doc lays out the architecture, the
prerequisites, and the step-by-step setup so Dave can both ship the
backend and learn the AWS surface in the process.

## Architecture

```
   iPhone / Simulator
          │
          ▼
   ┌──────────────────┐
   │   ALB (HTTPS)    │  TLS via ACM, two-AZ
   └────────┬─────────┘
            ▼
   ┌──────────────────┐
   │  ECS / Fargate   │  one task, arm64, :8080
   │  sous-chef       │  reads secrets at startup
   └────────┬─────────┘
            │
   ┌────────┴─────────┐
   ▼                  ▼
Supabase            OpenAI
(Postgres + Auth)   (chat + images)
```

- **Compute:** ECS on Fargate. One small task (0.25 vCPU, 0.5 GB) to
  start; bump if needed. Lambda is the wrong shape — our chat / recipe
  endpoints stream over SSE (long-lived connections, > 30 s). App
  Runner is in maintenance mode per the coding standard.
- **Image:** the multi-stage Dockerfile in `backend/Dockerfile` builds
  a static, distroless, non-root, arm64 binary. Pushed to ECR with
  immutable git-SHA tags.
- **Config:** all environment variables; secrets are fetched from AWS
  Secrets Manager at task start. The repo never sees them.
- **Networking:** an internet-facing ALB in two AZs, listening on
  443 with TLS terminated by a certificate from ACM, target group on
  port 8080.
- **Observability:** `slog` JSON → CloudWatch Logs via the awslogs
  driver. `/healthz` is the ALB health-check target. (Already
  implemented; unauthenticated by design.)
- **Infra-as-code:** Terraform under `infra/aws/`. The cluster, task
  definition, service, ALB, target group, and IAM roles are all in code
  — no console click-ops for anything that has to be reproducible.

## Prerequisites — Dave does these

1. **AWS account.** Sign up at <https://aws.amazon.com>. The first 12
   months include a generous free tier, but Fargate + ALB cost
   ~$50/month after that (see "Cost" below).
2. **IAM admin user.** **Never operate as the root user past account
   setup.** In the AWS Console → IAM → Users → create user
   `dave-admin`, attach the `AdministratorAccess` policy, generate an
   access key + secret. Save both.
3. **AWS CLI.** `brew install awscli` (or download the official `.pkg`
   from <https://awscli.amazonaws.com> if Homebrew is blocked).
   Then `aws configure` with the access key, secret, and a region —
   **us-east-1** is fine and matches the Supabase pooler region we're
   already on.
4. **Docker Desktop** for Mac (if not already installed) — for the
   local build + smoke-test. Apple-Silicon download from
   <https://www.docker.com/products/docker-desktop/>.
5. **Domain (optional, but needed for HTTPS).** Either point an
   existing domain at AWS (Route 53), or buy one through Route 53.
   You don't need a domain for the very first ALB-by-URL test, but you
   need one before the iOS app can hit a real HTTPS URL.

Once those five are in place, ping Astra. The rest below is mostly
"Astra runs commands, Dave watches and asks questions."

## Step 0 — Local Docker smoke-test (no AWS yet)

This proves the image builds and runs the way it will in Fargate.

```sh
cd ~/Sous-chef-1-claude/backend
docker build -t souschef-backend .
docker run --rm -p 8080:8080 --env-file .env souschef-backend
# in another terminal:
curl http://localhost:8080/healthz
# → ok
```

Stop with Ctrl+C. If `/healthz` returns `ok` the image is good.

## Step 1 — Push the image to ECR

```sh
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
REPO=souschef-backend

aws ecr create-repository --repository-name "$REPO" --region "$REGION"

aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin \
      "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

SHA=$(git rev-parse --short HEAD)
TAG="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:$SHA"
docker tag souschef-backend "$TAG"
docker push "$TAG"
```

Immutable tag = the git SHA. Never overwrite a tag in place.

## Step 2 — Store secrets in Secrets Manager

```sh
# Read the values from your local .env (don't echo them on the wire).
set -a; source .env; set +a

aws secretsmanager create-secret --name souschef/database-url \
  --secret-string "$DATABASE_URL"
aws secretsmanager create-secret --name souschef/supabase-project-url \
  --secret-string "$SUPABASE_PROJECT_URL"
aws secretsmanager create-secret --name souschef/openai-api-key \
  --secret-string "$OPENAI_API_KEY"
```

The Fargate task gets a role that allows `secretsmanager:GetSecretValue`
on these three ARNs and nothing else. Least privilege.

## Step 3 — Terraform: cluster, task, service, ALB

(Manifests under `infra/aws/`, added in a follow-up commit.)

```sh
cd ~/Sous-chef-1-claude/infra/aws
terraform init
terraform plan -var "image_tag=$SHA" -out plan.tfplan
terraform apply plan.tfplan
```

Plan output shows everything that will be created — read it before
apply. Astra walks through each resource the first time.

## Step 4 — Verify

```sh
ALB=$(terraform output -raw alb_dns)
curl https://$ALB/healthz
# → ok
```

Then a token-bearing request to a real endpoint:

```sh
TOKEN=...  # a Supabase access token from the iOS app's Keychain or a curl signin
curl -H "Authorization: Bearer $TOKEN" https://$ALB/api/auth/user
```

## Step 5 — Point the iOS app at the deployed URL

Edit `ios/SousChef/Networking/AppConfig.swift`:

```swift
static let backendBaseURL = URL(string: "https://api.souschef.example.com")!
```

Rebuild, run. The simulator now hits production. (Add a build-config
switch later so Debug → localhost and Release → ALB; one-line change.)

## Cost — what to expect

Running 24/7, no Spot:

| Item                     | Monthly |
|--------------------------|---------|
| Fargate task (0.25 vCPU, 0.5 GB) | ~$10 |
| ALB                      | ~$16 + data |
| Secrets Manager (3 secrets) | $1.20 |
| ECR storage              | <$1   |
| CloudWatch Logs          | free-tier covers it |
| **Total**                | **~$30–50** |

Cuts:
- **Fargate Spot** drops compute ~70 %.
- Drop the ALB and put the task behind a Cloudflare tunnel during
  dev — costs ~$0 but doesn't scale.

## What's in code vs what Dave does manually

| | Code | Dave |
|---|---|---|
| Account creation | | ✓ |
| IAM admin user | | ✓ |
| AWS CLI install + `aws configure` | | ✓ |
| Docker Desktop install | | ✓ |
| Domain + ACM cert | optional (Route 53 in TF) | ✓ |
| ECR repo + image push | one CLI script | walks through once |
| Secrets Manager entries | one CLI script | reviews values |
| Cluster / task / service / ALB | Terraform | reviews plan |
| iOS base URL switch | one-line edit | toggles when ready |

Everything in the "Code" column lives in this repo. Console click-ops
are off-limits for anything reproducible — see `CODING_STANDARDS.md`
`sc-06`.
