# Salesforce DevOps Pipeline

A production-grade Salesforce CI/CD pipeline for GitHub, with an AI-powered PR review bot, quick-deploy, rollback, drift detection, and a deployment ledger.

This README walks you through the setup from a fresh repo to your first production deployment, then explains how the AI review agent works on a real pull request.

---

## Table of Contents

1. [What you get](#what-you-get)
2. [Prerequisites](#prerequisites)
3. [Repository setup](#repository-setup)
4. [Salesforce setup — Connected App and JWT](#salesforce-setup--connected-app-and-jwt)
5. [GitHub setup — environments and secrets](#github-setup--environments-and-secrets)
6. [Anthropic API key — for the AI review agent](#anthropic-api-key--for-the-ai-review-agent)
7. [First-run baseline](#first-run-baseline)
8. [Branch and environment model](#branch-and-environment-model)
9. [How the AI review agent works](#how-the-ai-review-agent-works)
10. [Architectural improvements over a baseline pipeline](#architectural-improvements-over-a-baseline-pipeline)
11. [Operational runbooks](#operational-runbooks)
12. [Cost reference](#cost-reference)
13. [Troubleshooting](#troubleshooting)

---

## What you get

| Capability | File(s) |
|---|---|
| Validate then deploy on every push | `.github/workflows/_reusable-validate.yml`, `_reusable-deploy.yml` |
| Per-environment workflows (dev, qa, stage, pre-prod, prod) | `.github/workflows/sf*.yml` |
| Quick-deploy using validation IDs (60–80% faster prod deploys) | `.github/actions/sf-quick-deploy/action.yml` |
| Pre-deploy snapshot + manual rollback | `.github/workflows/rollback.yml` |
| Weekly drift detection (org vs `main`) with auto-issue | `.github/workflows/drift-detection.yml` |
| Deployment ledger committed to a separate branch | `_reusable-deploy.yml` (Record deployment step) |
| Two-layer PR review bot — static rules + Claude Sonnet | `.github/scripts/review.js`, `ai-review.js`, `rules/*` |
| Dynamic Apex test selection | `.github/scripts/GenerateSfdxCommand.js` |
| Stale branch cleanup | `.github/workflows/cleanup-branches.yml` |
| First-run baseline workflow | `.github/workflows/first-run-baseline.yml` |

---

## Prerequisites

- A GitHub repository (this one)
- Access to your target Salesforce orgs (Dev, QA, Stage, Pre-Prod, Prod)
- A workstation with `openssl`, `git`, and `sf` (Salesforce CLI v2) installed
- An Anthropic API key (only needed for the AI review layer — the rest of the pipeline works without it)

---

## Repository setup

Drop this bundle into your repo as-is, or migrate piece by piece:

```bash
# 1. Clone your existing repo
git clone https://github.com/<your-org>/<your-repo>.git
cd <your-repo>

# 2. Copy the bundle on top
unzip salesforce-pipeline-bundle.zip -d .

# 3. Install PR review bot dependencies (one-time, locally — CI does this too)
cd .github/scripts && npm install && cd ../..

# 4. Commit
git checkout -b chore/pipeline-setup
git add .
git commit -m "chore: bring in DevOps pipeline + AI review bot"
git push -u origin chore/pipeline-setup
```

Open a PR from `chore/pipeline-setup` to `develop` to verify the PR review bot fires (it will). Once you've reviewed its output, merge into `develop`.

---

## Salesforce setup — Connected App and JWT

JWT Bearer Flow is the auth mechanism. No passwords are stored anywhere.

### 1. Generate the keypair

On your workstation:

```bash
mkdir -p /tmp/sfjwt && cd /tmp/sfjwt
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr -subj "/C=GB/O=YourCompany/CN=ci-integration"
openssl x509 -req -sha256 -days 730 -in server.csr -signkey server.key -out server.crt
```

You now have:
- `server.key` — the **private key** (goes into GitHub secrets, never into git)
- `server.crt` — the **certificate** (uploaded to the Connected App)

### 2. Create the Connected App in Salesforce

In **each** target org (Dev, QA, Stage, Pre-Prod, Prod):

1. Setup → App Manager → **New Connected App**
2. Connected App Name: `CI/CD Integration`
3. API (Enable OAuth Settings):
   - **Enable OAuth Settings:** ✓
   - **Callback URL:** `http://localhost:1717/OauthRedirect` (placeholder — JWT doesn't use it)
   - **Use digital signatures:** ✓ — upload `server.crt`
   - **Selected OAuth Scopes:** `Manage user data via APIs (api)`, `Perform requests at any time (refresh_token, offline_access)`
4. Save. After creating, click **Manage** → **Edit Policies** → set **Permitted Users** to `Admin approved users are pre-authorized`.
5. Note the **Consumer Key** — this is `SF_CLIENT_ID`.

### 3. Create the integration user and permission set

1. Setup → Users → **New User** — e.g. `ci-integration@yourcompany.com.prod` (use a `+ci` alias on a real address you control). Profile: **System Administrator** is simplest; for a tighter setup, use a custom profile with API access.
2. Create a permission set `CI_CD_Integration` with:
   - System Permissions: **API Enabled**, **Modify Metadata Through Metadata API Functions**, **Modify All Data**
   - Object permissions matching what you actually deploy (Read/Create/Edit/Delete on standard and custom objects you touch)
3. Assign the permission set to the integration user.
4. Back on the Connected App: **Manage** → **Manage Profiles** (or Permission Sets) — pre-authorize the integration user's profile/permission set.

### 4. Test the JWT flow locally

```bash
sf org login jwt \
  --client-id <SF_CLIENT_ID> \
  --jwt-key-file /tmp/sfjwt/server.key \
  --username ci-integration@yourcompany.com.prod \
  --instance-url https://login.salesforce.com \
  --alias prod-ci

sf org display --target-org prod-ci
```

If that works, the GitHub Actions auth will work too. Repeat for each org you want the pipeline to deploy to.

---

## GitHub setup — environments and secrets

The pipeline uses **GitHub Environments** so each Salesforce org has its own scoped secrets and (for prod) approval gates.

### 1. Create environments

Repository → **Settings** → **Environments** → **New environment** for each:

- `sfdev`
- `sfqa`
- `sfstage`
- `sfprod`
- `sfprod-validation` (used by the pre-prod-validation and drift-detection workflows)

For `sfprod`: enable **Required reviewers** and add yourself + at least one other person. This is your manual approval gate before any prod deploy.

### 2. Add secrets to each environment

Inside each environment, **Add secret**:

| Secret name | Value |
|---|---|
| `SF_CLIENT_ID` | The Connected App Consumer Key for that org |
| `SF_USERNAME` | Integration user username for that org |
| `SF_LOGIN_URL` | `https://login.salesforce.com` for prod, `https://test.salesforce.com` for sandboxes |
| `SF_JWT_KEY` | Full contents of `server.key` (paste the whole `-----BEGIN PRIVATE KEY-----` block, with newlines) |

> Tip: you can use the **same** JWT keypair across all orgs (one Connected App per org, all trusting the same cert). This means just one `SF_JWT_KEY` to rotate quarterly — the rotation procedure becomes generating a new key, uploading the new cert to all five Connected Apps, then updating the secret.

### 3. Branch protection

Repository → **Settings** → **Branches** → **Add rule**:

- For `main`, `develop`, `qa`, `stage`:
  - Require pull request reviews
  - Require status checks: `Salesforce PR Review`
  - Require linear history (recommended)
- For `main` only:
  - Restrict who can push (only people who can approve the `sfprod` environment)

---

## Anthropic API key — for the AI review agent

The AI review layer is **optional** — without an API key, only the static rules layer runs and PRs still get reviewed. With a key, you also get the cross-file impact analysis described below.

### 1. Get an API key

1. Sign in at <https://console.anthropic.com>
2. Workspaces → your workspace → **API Keys** → **Create Key**
3. Name it `github-pr-review-bot` so usage shows up cleanly on the Usage page
4. Copy the key (starts with `sk-ant-`)

### 2. Add to GitHub

Repository → **Settings** → **Secrets and variables** → **Actions** → **Repository secrets** → **New repository secret**:

| Name | Value |
|---|---|
| `ANTHROPIC_API_KEY` | The `sk-ant-...` key |

It's a **repository** secret (not environment-scoped) because PR reviews run before any environment context is established.

### 3. Verify

Open any PR. Within ~30 seconds the `Salesforce PR Review` workflow should run and post a review. Look at the workflow log — you'll see:

```
AI review: 3 logic file(s), 4 context file(s), ~3,200 input tokens estimated
AI review: tokens used — input: 3418, output: 612, cache_read: 820, cache_write: 0
```

That's the AI layer running. If you don't see those lines, the layer was skipped (XML-only PR) or the key isn't set.

---

## First-run baseline

The validate workflow needs a **starting commit** to compute the delta against. On a brand-new branch with no prior successful runs, it falls back to the merge-base with `develop`. To avoid relying on that fallback, run the baseline workflow once per branch:

1. **Actions** → **First-Run Baseline** → **Run workflow**
2. Pick the branch (`develop`, `qa`, `stage`, `main`)
3. Run

Subsequent pushes on that branch use the previous successful run as the delta start point. You only need to do this once per branch, ever.

---

## Branch and environment model

```
feature/* ──PR──▶ develop ──▶ qa ──▶ stage ──▶ pre-prod-validation ──▶ main
              │           │       │           │                       │
              │ sfdev.yml │ sfqa  │ sfstage   │ sfpreprodvalidation   │ sfprod.yml
              │ → SF Dev  │ → QA  │ → Stage   │ → Pre-Prod (val only) │ → Prod
              │           │       │           │                       │
   PR review ─┘           │       │           │                       │
   (every PR              │       │           │                       │
    to any branch)        │       │           │                       │
                          │       │           │                       │
                          └───────┴───────────┴───────────────────────┘
                          Each push triggers validate → quick-deploy
```

| Branch | Environment | Test level | Approval gate |
|---|---|---|---|
| `develop` | sfdev | RunSpecifiedTests | none |
| `qa` | sfqa | RunLocalTests | none |
| `stage` | sfstage | RunLocalTests | none |
| `pre-prod-validation` | sfprod-validation | RunAllTestsInOrg | n/a (validate-only) |
| `main` | sfprod | RunAllTestsInOrg | manual reviewers |

Two-stage pattern within each environment:

1. **Validate** — generates delta, snapshots current org state for rollback, runs dry-run deploy, captures a 10-day-valid validation ID.
2. **Deploy** — uses **quick-deploy** with that validation ID (no test re-run, much faster). Falls back to a full deploy if no validation ID was provided.

Flags that control the pipeline:

| Output | Meaning |
|---|---|
| `nothing_to_deploy=true` | No metadata changes — deploy job is skipped entirely |
| `validation_id=<id>` | Quick-deploy ID from the validate job, passed to deploy |

---

## How the AI review agent works

This is the bit you specifically asked about, so here's the full picture.

### When it runs

On every PR opened or updated against `develop`, `qa`, `stage`, or `main`. It does **not** run on direct pushes — it's a code-review tool, not a deployment guard.

### Two layers, one review

The bot runs two independent layers and merges their findings into a single PR review:

**Layer 1 — Static rules** (`.github/scripts/rules/`)

Deterministic pattern-matching across 30+ rules. Fires regardless of API key. Examples:

- `SF-APEX-001` — SOQL inside a for/while loop
- `SF-APEX-002` — DML inside a for/while loop
- `SF-APEX-004` — silent exception swallowing (catch block that only logs)
- `SF-APEX-005` — SOQL without `WITH USER_MODE` / `WITH SECURITY_ENFORCED`
- `SF-APEX-006` — `@AuraEnabled` method without try/catch
- `SF-TRIG-001` — too much logic in trigger body (use a handler)
- `SF-TRIG-002` / `003` — SOQL/DML in a trigger body
- `SF-LWC-001` — hardcoded URL
- `SF-LWC-002` — imperative Apex with `.then` but no `.catch`
- `SF-LWC-003` — `document.querySelector` (use template.querySelector)
- `SF-SEC-001` — `global` access modifier overuse
- `SF-SEC-002` — class without explicit `with sharing` / `without sharing` / `inherited sharing`
- `SF-META-001` — API version below team minimum
- `SF-META-002` — destructive change (file deletion)

**Layer 2 — Claude Sonnet AI agent** (`.github/scripts/ai-review.js`)

Read-only — explicitly instructed never to write code, only describe issues. Catches things pattern-matching cannot:

| Category | What it spots |
|---|---|
| CRUD/FLS | `@AuraEnabled` method missing `Schema.sObjectType.X.isCreateable()` checks |
| Sharing | `without sharing` on a class that exposes user-facing data |
| Async | `@future` calling another `@future`, Queueable not chained correctly |
| Trigger ↔ Flow | Record-triggered flow on the same object/event as the trigger |
| Cross-file impact | Field rename in `Account.object-meta.xml` breaking other Apex that references it |
| Method signatures | Public method param change breaking callers elsewhere in the repo |
| LWC reactivity | Stale state between `@wire` and imperative calls; missing error path |
| Flow null-safety | Get Records → reference fields without "no records" branch |

The AI layer also receives **context files** automatically. If your PR changes `AccountTrigger.cls`, the agent gets:
- Other triggers on Account (to spot execution-order conflicts)
- Flows referencing Account (to spot dual-automation)
- `Account.object-meta.xml`

So it's reasoning over the cross-file blast radius, not just the diff.

### Cost guards (this is the engineering work)

The AI layer is bounded by five guards in `ai-review.js`. In order of impact:

| # | Guard | Effect |
|---|---|---|
| 1 | Skip non-logic PRs | XML-only PRs (profiles, translations, layouts) never call the API — $0.00 |
| 2 | Diff-only for metadata | Non-logic files send the diff only, not full content |
| 3 | Hard input cap (~12,500 tokens) | Context files are dropped from the tail until the request fits |
| 4 | Output cap (`max_tokens: 2048`) | Caps the response at ~15 findings |
| 5 | Context file limit (max 8) | Even with budget, the agent never sees more than 8 related files |

Token usage is logged on every run so you can monitor cost trends.

### What a finding looks like

The bot posts a single GitHub PR review with inline comments on changed lines. Each finding has:

```
🔴 SF-APEX-001 — SOQL query inside a loop. Move the query outside
the loop and process results in bulk.

Suggestion: Query before the loop, then iterate over the result set.
```

🔴 = high severity, 🟡 = medium, 🔵 = low. **High-severity findings request changes** (the PR cannot be merged until either fixed or dismissed). Medium and low post as comments only.

Findings outside the diff (e.g. impact on a file your PR didn't touch) appear in a summary table in the review body.

### What it deliberately does NOT do

- Never writes or suggests code (only descriptions)
- Never requests changes for low/medium findings — only for high
- Never re-reviews on its own; push a new commit to trigger a new review
- Never sees secrets, only repo source

---

## Architectural improvements over a baseline pipeline

These are the architect-level additions over a vanilla `validate → deploy` setup:

### 1. Quick-deploy with validation ID handoff

The validate job captures the validation deployment ID (valid for 10 days). The deploy job takes that ID and runs `sf project deploy quick`, which **skips re-running Apex tests**. Typical effect:

- Validate (once): full Apex run, 25–40 minutes
- Deploy (immediate): quick-deploy, 3–8 minutes

Same correctness, ~70% less wall time on the deploy itself.

### 2. Pre-deploy snapshot + rollback workflow

Before deploying, the validate job retrieves the **current** state of every metadata file in the delta and uploads it as a workflow artifact (`rollback-snapshot-<env>-<run-id>`, retained 30 days).

If a deploy goes bad, run the **Rollback Deployment** workflow with the offending run ID. It downloads the snapshot and redeploys it — restoring the exact pre-deployment state.

> Limitation: NEW components can't be auto-rolled back this way (Salesforce has no rollback for creates). The workflow detects this and tells you.

### 3. Drift detection

Weekly job that retrieves prod metadata for tracked types and diffs it against `main`. If anything's changed in prod via Setup that didn't come through the pipeline, an issue is auto-opened (or appended to the existing one). Catches the "someone changed it in production directly" class of bugs.

### 4. Deployment ledger

Every deploy writes a JSON record (timestamp, actor, commit, deploy ID, validation ID, outcome) and the workflow auto-commits it to a `deployments-ledger` branch. This is your audit trail. SOC 2 / change advisory board / "who deployed what when" — all answerable in `git log deployments-ledger`.

### 5. Production guardrails

- **`RunAllTestsInOrg` mandatory for prod** (hardcoded in `sfprod.yml`)
- **Manual approval gate** on the `sfprod` environment via GitHub environment protection
- **Quick-deploy** kicks in only after that approval is given
- **Branch protection on `main`** restricts pushes to approvers

### 6. First-run baseline + merge-base fallback

The standard "what's the previous successful run?" lookup falls back to the merge-base with `develop` if no successful run exists. Means a brand-new branch can run without a manual baseline step — but the baseline workflow is still there for when you want explicit control.

---

## Operational runbooks

### "I need to deploy to prod"

1. Open PR from your feature branch → `develop`
2. Wait for **PR review bot** to comment; address any 🔴 findings
3. Get human approval, merge to `develop` — `sfdev.yml` runs automatically
4. Open PR `develop` → `qa`, repeat through `stage` and `pre-prod-validation`
5. Open PR `pre-prod-validation` → `main`
6. On merge, `sfprod.yml` runs validate; **the deploy job pauses for manual approval**
7. Approver clicks **Review deployments** → **Approve** in the workflow run
8. Quick-deploy completes, ledger entry written

### "Prod broke — get me back"

1. Find the bad workflow run: **Actions** → **SF Prod** → bad run → copy the **Run ID**
2. **Actions** → **Rollback Deployment** → **Run workflow**
3. Environment: `sfprod`, Run ID: the one you copied, Confirm: type `ROLLBACK`
4. Approve the `sfprod` environment gate again
5. Snapshot redeploys

### "Drift was detected"

1. The auto-opened drift issue has the diff
2. For each item: either reverse-engineer it back into git (and PR through the normal flow) or revert it in the org
3. Close the issue once the next drift run shows no diff

### "Rotate JWT keys"

```bash
# Generate new pair
openssl genrsa -out server-new.key 2048
openssl req -new -key server-new.key -out server-new.csr -subj "/C=GB/O=YourCompany/CN=ci-integration"
openssl x509 -req -sha256 -days 730 -in server-new.csr -signkey server-new.key -out server-new.crt

# In Salesforce: each Connected App → Edit → upload server-new.crt → Save
# In GitHub: each environment → SF_JWT_KEY → Update with contents of server-new.key
# Run sfdev.yml manually — if it passes, rotation is complete
```

---

## Cost reference

Based on `claude-sonnet-4-5`. Actual usage is logged on every PR review run.

| PR type | Typical cost | Notes |
|---|---|---|
| XML / metadata-only | $0.00 | Cost guard #1 — API never called |
| Small Apex/LWC PR (1–3 files) | $0.01 – $0.03 | Layer 2 fires, small context |
| Medium PR (4–8 logic files) | $0.03 – $0.08 | Full context window used |
| Large PR (>8 files) | $0.08 – $0.15 | Cost guard #5 caps at 8 context files |

A team doing 50–100 PRs/week is looking at **$5–$15/week** for the AI layer. The static layer is always free.

---

## Troubleshooting

**The PR review workflow doesn't fire**
- Check the PR base branch — the workflow only triggers on PRs to `develop`, `qa`, `stage`, `main`
- Check workflow permissions: **Settings** → **Actions** → **General** → **Workflow permissions** = Read and write

**JWT auth fails with `OAUTH_APP_ACCESS_DENIED`**
- The integration user isn't pre-authorized on the Connected App. Manage → Manage Profiles or Permission Sets.

**JWT auth fails with `JWT validation failed`**
- The `SF_JWT_KEY` secret is missing the `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` lines, or has Windows line endings
- Re-paste the key. On macOS/Linux: `cat server.key | pbcopy` or `xclip -selection clipboard < server.key`

**Quick-deploy fails with "validation ID expired"**
- Salesforce's 10-day window has passed. Re-run the validate workflow to get a fresh ID, or let the deploy fall back to a full deploy.

**`No prior successful run found`**
- Run **First-Run Baseline** for that branch, then push again.

**AI layer is silently skipping**
- Check the workflow log. If it says `ANTHROPIC_API_KEY not set — skipping AI review layer`, the secret isn't configured.
- If it says `no logic files changed — skipping (cost guard 1)`, that's expected — the PR is XML-only.

**`Salesforce PR Review` posts no findings on a PR I expected to fail**
- Look at the workflow log under "Run review" — confirm static rules ran and how many findings the AI layer returned. Both layers might genuinely have nothing to say.

---

## Repository layout

```
.github/
├── workflows/
│   ├── _reusable-validate.yml        # shared validate logic
│   ├── _reusable-deploy.yml          # shared deploy logic with quick-deploy
│   ├── sfdev.yml                     # develop → SF Dev
│   ├── sfqa.yml                      # qa → SF QA
│   ├── sfstage.yml                   # stage → SF Stage
│   ├── sfprod.yml                    # main → SF Prod (with approval gate)
│   ├── sfpreprodvalidation.yml       # validation-only on pre-prod
│   ├── salesforce-pr-review.yml      # PR review bot trigger
│   ├── rollback.yml                  # manual rollback
│   ├── drift-detection.yml           # weekly org-vs-main diff
│   ├── first-run-baseline.yml        # one-time baseline per branch
│   └── cleanup-branches.yml          # weekly stale branch cleanup
├── actions/
│   ├── install-sf-cli/               # composite: install @salesforce/cli
│   ├── install-plugin/               # composite: install an SF plugin
│   ├── sf-login/                     # composite: JWT auth
│   ├── generate-delta/               # composite: sfdx-git-delta
│   ├── sf-check-deploy/              # composite: validate (returns validation_id)
│   ├── sf-deploy/                    # composite: full deploy
│   ├── sf-quick-deploy/              # composite: quick-deploy from validation_id
│   └── run-scripts/                  # composite: run pre/post Apex scripts
├── scripts/
│   ├── review.js                     # PR bot orchestrator
│   ├── ai-review.js                  # Claude Sonnet review layer
│   ├── GenerateSfdxCommand.js        # dynamic Apex test selection
│   ├── package.json                  # bot dependencies
│   ├── utils/diffParser.js           # PR diff parser
│   └── rules/                        # static rules (apex, trigger, lwc, security, metadata)
├── pre-deployment/                   # *.apex files run BEFORE every deploy
└── post-deployment/                  # *.apex files run AFTER every deploy

force-app/main/default/               # Salesforce DX project (your code)
manifest/package.xml                  # used by drift detection
deployments/                          # ledger entries (auto-committed)
sfdx-project.json
```

---

## Credits and license

Static rule design and the validate→quick-deploy pattern are adapted from common Salesforce DevOps practices. The AI review layer architecture (read-only, two-layer, cost-guarded) is inspired by the [`gabrielolv/salesforce-devops-pipeline`](https://github.com/gabrielolv/salesforce-devops-pipeline) project and adapted for this repo's needs.
