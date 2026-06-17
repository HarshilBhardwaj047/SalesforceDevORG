# Salesforce DevOps Pipeline

A production-grade Salesforce CI/CD pipeline for GitHub, with an AI-powered PR review bot, quick-deploy, rollback, drift detection, automatic cherry-picking, and a deployment ledger.

This README covers setup from a fresh repo to first production deployment, a complete walkthrough of every workflow trigger and execution order, and all improvements shipped in the `chore/workflow-improvements` branch.

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
9. [Workflow trigger map — full execution order](#workflow-trigger-map--full-execution-order)
10. [Workflow reference — every file explained](#workflow-reference--every-file-explained)
11. [How the AI review agent works](#how-the-ai-review-agent-works)
12. [Architectural improvements](#architectural-improvements)
13. [Operational runbooks](#operational-runbooks)
14. [Cost reference](#cost-reference)
15. [Troubleshooting](#troubleshooting)
16. [Repository layout](#repository-layout)

---

## What you get

| Capability | Workflow / File |
|---|---|
| Validate then deploy on every push | `_reusable-validate.yml`, `_reusable-deploy.yml` |
| Per-environment pipelines (dev, qa, stage, pre-prod, prod) | `sfdev.yml`, `sfqa.yml`, `sfstage.yml`, `sfpreprodvalidation.yml`, `sfprod.yml` |
| Quick-deploy using validation IDs (60–80% faster prod deploys) | `.github/actions/sf-quick-deploy/action.yml` |
| Pre-deploy snapshot + manual rollback with configurable test level | `rollback.yml` |
| Weekly drift detection with auto-open **and auto-close** of issues | `drift-detection.yml` |
| Deployment ledger committed to a separate branch | `_reusable-deploy.yml` (Record deployment step) |
| Two-layer PR review bot — static rules + Claude Sonnet (skips Dependabot) | `.github/scripts/review.js`, `ai-review.js`, `rules/*` |
| Dynamic Apex test selection | `.github/scripts/GenerateSfdxCommand.js` |
| Stale branch cleanup (runs live on schedule, dry-run on manual dispatch) | `cleanup-branches.yml` |
| Auto cherry-pick Cherry-prefixed PRs from `develop` → `qa` | `cherry-pick-workflow.yml` |
| First-run baseline workflow | `first-run-baseline.yml` |
| Concurrency guards on every workflow (no duplicate deploys) | All workflows |
| Timeout guards on every job (no hung runners) | All workflows |
| Shell injection hardening (all user inputs via `env:` blocks) | All `run:` steps |

---

## Prerequisites

- A GitHub repository (this one)
- Access to your target Salesforce orgs (Dev, QA, Stage, Pre-Prod, Prod)
- A workstation with `openssl`, `git`, and `sf` (Salesforce CLI v2) installed
- An Anthropic API key (optional — only needed for the AI review layer)

---

## Repository setup

```bash
# 1. Clone your existing repo
git clone https://github.com/<your-org>/<your-repo>.git
cd <your-repo>

# 2. Copy the bundle on top
unzip salesforce-pipeline-bundle.zip -d .

# 3. Install PR review bot dependencies (one-time locally — CI does this too)
cd .github/scripts && npm install && cd ../..

# 4. Commit
git checkout -b chore/pipeline-setup
git add .
git commit -m "chore: bring in DevOps pipeline + AI review bot"
git push -u origin chore/pipeline-setup
```

Open a PR from `chore/pipeline-setup` to `develop` to verify the PR review bot fires. Once reviewed, merge into `develop`.

---

## Salesforce setup — Connected App and JWT

JWT Bearer Flow is the auth mechanism. No passwords are stored anywhere.

### 1. Generate the keypair

```bash
mkdir -p /tmp/sfjwt && cd /tmp/sfjwt
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr -subj "/C=GB/O=YourCompany/CN=ci-integration"
openssl x509 -req -sha256 -days 730 -in server.csr -signkey server.key -out server.crt
```

- `server.key` — the **private key** (goes into GitHub secrets, never into git)
- `server.crt` — the **certificate** (uploaded to the Connected App)

### 2. Create the Connected App in Salesforce

In **each** target org (Dev, QA, Stage, Pre-Prod, Prod):

1. Setup → App Manager → **New Connected App**
2. API (Enable OAuth Settings):
   - **Enable OAuth Settings:** ✓
   - **Callback URL:** `http://localhost:1717/OauthRedirect`
   - **Use digital signatures:** ✓ — upload `server.crt`
   - **Selected OAuth Scopes:** `Manage user data via APIs (api)`, `Perform requests at any time (refresh_token, offline_access)`
3. Save. **Manage** → **Edit Policies** → set **Permitted Users** to `Admin approved users are pre-authorized`.
4. Note the **Consumer Key** — this is `SF_CLIENT_ID`.

### 3. Create the integration user and permission set

1. Setup → Users → **New User** (e.g., `ci-integration@yourcompany.com.prod`). Profile: **System Administrator** for simplest setup.
2. Create a permission set `CI_CD_Integration` with **API Enabled**, **Modify Metadata Through Metadata API Functions**, **Modify All Data**.
3. Assign the permission set to the integration user.
4. Back on the Connected App: **Manage** → pre-authorize the integration user's profile/permission set.

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

If this works, the GitHub Actions auth will work too. Repeat for each org.

---

## GitHub setup — environments and secrets

### 1. Create environments

Repository → **Settings** → **Environments** → **New environment** for each:

- `sfdev`
- `sfqa`
- `sfstage`
- `sfprod`
- `sfprod-validation` (used by pre-prod-validation and drift-detection)

For `sfprod`: enable **Required reviewers** and add yourself + at least one other person. This is the manual approval gate before any prod deploy.

### 2. Add secrets to each environment

| Secret name | Value |
|---|---|
| `SF_CLIENT_ID` | Connected App Consumer Key for that org |
| `SF_USERNAME` | Integration user username for that org |
| `SF_LOGIN_URL` | `https://login.salesforce.com` for prod; `https://test.salesforce.com` for sandboxes |
| `SF_JWT_KEY` | Full contents of `server.key` including `-----BEGIN/END PRIVATE KEY-----` lines |

> You can use one JWT keypair across all orgs — just upload the same `server.crt` to each Connected App. One `SF_JWT_KEY` to rotate quarterly.

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

The AI review layer is **optional** — without a key, only the static rules layer runs. With a key you also get cross-file impact analysis.

### 1. Get an API key

1. Sign in at <https://console.anthropic.com>
2. Workspaces → your workspace → **API Keys** → **Create Key**
3. Name it `github-pr-review-bot`

### 2. Add to GitHub

Repository → **Settings** → **Secrets and variables** → **Actions** → **Repository secrets** → **New repository secret**:

| Name | Value |
|---|---|
| `ANTHROPIC_API_KEY` | The `sk-ant-...` key |

This is a **repository** secret (not environment-scoped) because PR reviews run before any environment context is established.

### 3. Verify

Open any PR. The `Salesforce PR Review` workflow runs automatically. Look at the log for:

```
AI review: 3 logic file(s), 4 context file(s), ~3,200 input tokens estimated
AI review: tokens used — input: 3418, output: 612, cache_read: 820, cache_write: 0
```

If you don't see those lines, the layer was skipped (XML-only PR) or the key isn't set.

---

## First-run baseline

The validate workflow needs a starting commit to compute the delta. On a brand-new branch with no prior successful runs it falls back to the merge-base with `develop`. To use an explicit baseline:

1. **Actions** → **First-Run Baseline** → **Run workflow**
2. Pick the branch (`develop`, `qa`, `stage`, `main`)
3. Run

The step summary will show:

```
## Baseline established
Branch: develop
Commit: abc1234...
Subsequent deployment runs on this branch will use this commit as the start point for delta generation.
```

You only need to do this once per branch, ever.

---

## Branch and environment model

```
feature/* ──PR──▶ develop ──push──▶ qa ──push──▶ stage ──push──▶ pre-prod-validation ──push──▶ main
              │                │                                                              │
              │ PR Review Bot  │ Cherry-pick                                                  │
              │ (static+AI)    │ (Cherry-prefixed                                             │
              │                │  PRs → qa)                                                   │
              ▼                ▼                                                              ▼
         sfdev.yml          sfqa.yml          sfstage.yml    sfpreprodvalidation.yml     sfprod.yml
         → SF Dev org       → SF QA org       → SF Stage org → Pre-Prod (validate only)  → SF Prod org
                                                                                           ⏸ Manual approval
```

| Branch | Environment | Test level | Approval gate | Notes |
|---|---|---|---|---|
| `develop` | `sfdev` | RunSpecifiedTests | None | Dynamic test selection via `GenerateSfdxCommand.js` |
| `qa` | `sfqa` | RunLocalTests | None | Also receives auto cherry-picks from `develop` |
| `stage` | `sfstage` | RunLocalTests | None | |
| `pre-prod-validation` | `sfprod-validation` | RunAllTestsInOrg | None | Validate-only — never deploys |
| `main` | `sfprod` | RunAllTestsInOrg | **Manual reviewer approval** | Quick-deploy after approval |

### Two-stage pattern inside each environment

Every push to `develop`, `qa`, `stage`, `pre-prod-validation`, or `main` runs two jobs in sequence:

```
Push to branch
     │
     ▼
┌─────────────────────────────────────────────────────────┐
│  Job 1: validate  (calls _reusable-validate.yml)        │
│  ─────────────────────────────────────────────────────  │
│  1. Checkout (full history)                             │
│  2. Install SF CLI + sfdx-git-delta plugin              │
│  3. Resolve start commit                                │
│     ├─ If manual override: use that commit              │
│     ├─ If prior successful run on branch: use that SHA  │
│     └─ Fallback: git merge-base with origin/develop     │
│  4. Generate delta package (start..HEAD)                │
│  5. If nothing_to_deploy=true → skip to summary         │
│  6. Generate dynamic Apex test list                     │
│  7. Authenticate to Salesforce (JWT)                    │
│  8. Snapshot current org state → upload artifact        │
│     (rollback-snapshot-<env>-<run_id>, 30-day retention)│
│  9. Validate deployment (dry-run, captures validation_id)│
│  10. Append step summary                                │
│                                                         │
│  Outputs: nothing_to_deploy, validation_id, delta_summary│
└─────────────────────────────────────────────────────────┘
     │
     │ (if nothing_to_deploy != 'true')
     ▼
┌─────────────────────────────────────────────────────────┐
│  Job 2: deploy  (calls _reusable-deploy.yml)            │
│  ─────────────────────────────────────────────────────  │
│  1. Checkout (full history)                             │
│  2. Install SF CLI + sfdx-git-delta plugin              │
│  3. Authenticate to Salesforce (JWT)                    │
│  4. Run pre-deployment Apex scripts (.github/pre-deployment/*.apex)│
│  5a. Quick-deploy (if validation_id provided)           │
│      └─ sf project deploy quick --job-id <validation_id>│
│  5b. Full deploy (if no validation_id)                  │
│      ├─ Regenerate delta                                │
│      └─ sf project deploy start --manifest delta/...   │
│  6. Run post-deployment Apex scripts (.github/post-deployment/*.apex)│
│  7. Record deployment → commit JSON to deployments-ledger branch│
│  8. Append step summary                                 │
└─────────────────────────────────────────────────────────┘
```

> For `sfprod` only: the deploy job is protected by the `sfprod` GitHub environment — it pauses and waits for a human approver before running. For all other environments, it runs immediately after validate succeeds.

---

## Workflow trigger map — full execution order

This section shows exactly **what event triggers each workflow**, what it does step-by-step, and how workflows interact.

---

### 1. Developer pushes to a feature branch

**Trigger:** `push` to any branch (no workflow fires — but the PR review bot fires on PR open)

---

### 2. Developer opens or updates a PR

**Trigger:** `pull_request` types `[opened, synchronize, reopened]` to `develop`, `qa`, `stage`, or `main`

```
PR opened/updated
      │
      ├─ Skip if: PR author is dependabot[bot]
      │
      ▼
salesforce-pr-review.yml
  concurrency: pr-review-<PR number> (cancel-in-progress: true — old reviews superseded)
  timeout: 15 min
      │
      ├─ Checkout PR head commit
      ├─ Setup Node 20
      ├─ npm install (review bot deps)
      └─ Run review.js (continue-on-error: true — review bot crash never blocks merge)
           │
           ├─ Layer 1: Static rules engine
           │    ├─ Parse PR diff
           │    ├─ Run 30+ pattern rules (SOQL in loop, DML in loop, sharing violations, etc.)
           │    └─ Collect findings with severity/location
           │
           └─ Layer 2: Claude Sonnet AI (only if ANTHROPIC_API_KEY is set and PR has logic files)
                ├─ Cost guard: skip if XML-only PR
                ├─ Collect changed logic files + up to 8 context files
                ├─ Cap input to ~12,500 tokens
                ├─ Call Claude Sonnet with read-only instruction
                └─ Collect AI findings
                     │
                     └─ Post single PR review with inline comments
                          🔴 high = REQUEST_CHANGES
                          🟡 medium / 🔵 low = COMMENT only
```

---

### 3. Push to `develop`

**Trigger:** `push` to `develop` branch OR `workflow_dispatch` with optional `commit_hash`

```
Push to develop
      │
      ▼
sfdev.yml
  concurrency: deploy-sfdev (cancel-in-progress: false — no duplicate deploys)
  permissions: contents:write, pull-requests:read, actions:read
      │
      ├─ Job 1: validate (calls _reusable-validate.yml, environment: sfdev, test_level: RunSpecifiedTests)
      │    └─ [see two-stage pattern above]
      │
      └─ Job 2: deploy (calls _reusable-deploy.yml, only if nothing_to_deploy != 'true')
           └─ [see two-stage pattern above]
```

---

### 4. PR merged to `develop` with a "Cherry"-prefixed title

**Trigger:** `pull_request` type `[closed]` targeting `develop`, merged=true, title starts with "Cherry"

```
PR merged to develop (title starts with "Cherry")
      │
      ▼
cherry-pick-workflow.yml
  concurrency: cherry-pick-<PR number> (cancel-in-progress: false)
  timeout: 15 min
      │
      ├─ Checkout full history
      ├─ Configure git user (via env var — injection-safe)
      └─ Cherry-pick PR commit into qa
           │
           ├─ Guard: exit if merge_commit_sha is empty
           ├─ Fetch origin
           ├─ Checkout qa branch (create from origin/qa if missing)
           ├─ Detect commit type: count parents of merge_commit_sha
           │    ├─ 2+ parents = regular merge → git cherry-pick -m 1 -x <sha>
           │    └─ 1 parent = squash merge → git cherry-pick -x <sha>
           ├─ On conflict: abort and fail with ::error:: annotation
           └─ git push origin qa
```

> Pushing to `qa` triggers `sfqa.yml` automatically — the cherry-picked change is deployed to QA without any manual step.

---

### 5. Push to `qa`

**Trigger:** `push` to `qa` branch OR `workflow_dispatch`

```
Push to qa (direct push or triggered by cherry-pick)
      │
      ▼
sfqa.yml
  concurrency: deploy-sfqa (cancel-in-progress: false)
  permissions: contents:write, pull-requests:read, actions:read
      │
      ├─ Job 1: validate (environment: sfqa, test_level: RunLocalTests)
      └─ Job 2: deploy (if nothing_to_deploy != 'true')
```

---

### 6. Push to `stage`

**Trigger:** `push` to `stage` branch OR `workflow_dispatch`

```
Push to stage
      │
      ▼
sfstage.yml
  concurrency: deploy-sfstage (cancel-in-progress: false)
  permissions: contents:write, pull-requests:read, actions:read
      │
      ├─ Job 1: validate (environment: sfstage, test_level: RunLocalTests)
      └─ Job 2: deploy (if nothing_to_deploy != 'true')
```

---

### 7. Push to `pre-prod-validation`

**Trigger:** `push` to `pre-prod-validation` OR `workflow_dispatch`

```
Push to pre-prod-validation
      │
      ▼
sfpreprodvalidation.yml
  concurrency: deploy-sfprod-validation (cancel-in-progress: false)
  permissions: contents:read, pull-requests:read, actions:read
      │
      └─ Job 1: validate ONLY (environment: sfprod-validation, test_level: RunAllTestsInOrg)
           └─ No deploy job — this workflow only validates, never deploys
                Purpose: dry-run the eventual prod deploy against a Pre-Prod mirror org
```

---

### 8. Push to `main` (production deployment)

**Trigger:** `push` to `main` OR `workflow_dispatch`

```
Push to main
      │
      ▼
sfprod.yml
  concurrency: deploy-sfprod (cancel-in-progress: false)
  permissions: contents:write, pull-requests:read, actions:read
      │
      ├─ Job 1: validate (environment: sfprod, test_level: RunAllTestsInOrg)
      │    └─ Full test suite, typically 25–40 min
      │    └─ Outputs: validation_id (valid 10 days)
      │
      └─ Job 2: deploy ── needs: [validate] ── environment: sfprod
           │
           ⏸ PAUSED — waits for manual approval from sfprod environment reviewers
           │
           ▼ (after human approves in GitHub Actions UI)
           └─ Quick-deploy using validation_id (3–8 min, no test re-run)
                └─ Writes record to deployments-ledger branch
```

---

### 9. Manual rollback

**Trigger:** `workflow_dispatch` only — requires `environment`, `run_id`, `confirm=ROLLBACK`, optional `test_level`

```
Manual: Actions → Rollback Deployment → Run workflow
  inputs: environment, run_id, confirm="ROLLBACK", test_level (default: RunLocalTests)
      │
      ▼
rollback.yml
  concurrency: rollback-<environment> (cancel-in-progress: false)
  timeout: 90 min
      │
      ├─ Guard: if confirm != 'ROLLBACK', job is skipped entirely
      ├─ Checkout
      ├─ Install SF CLI
      ├─ Download rollback-snapshot-<environment>-<run_id> artifact
      │    (artifact uploaded by _reusable-validate.yml, retained 30 days)
      ├─ Authenticate to Salesforce
      ├─ Guard: if snapshot is empty → ::error:: and exit
      ├─ sf project deploy start --source-dir rollback-snapshot
      │    --test-level <test_level input> (env-var safe)
      └─ Append rollback summary to step summary
```

> Rollback also requires approval through the target environment gate (e.g., `sfprod` for production rollbacks).

---

### 10. Weekly drift detection (Mondays 06:00 UTC)

**Trigger:** `schedule` cron `0 6 * * 1` OR `workflow_dispatch`

```
Monday 06:00 UTC (or manual dispatch)
      │
      ▼
drift-detection.yml
  timeout: 30 min
  permissions: contents:read, issues:write
      │
      ├─ Checkout main
      ├─ Install SF CLI
      ├─ Authenticate to Salesforce (sfprod-validation environment)
      ├─ sf project retrieve start --manifest manifest/package.xml --output-dir drift-check
      │    (no || true — failures surface and fail the job)
      ├─ diff -r force-app/main/default drift-check/main/default
      │    ├─ drift_found=false → [auto-close step]
      │    └─ drift_found=true  → [open/update issue step]
      │
      ├─ [if drift_found=true]
      │    ├─ Upload drift-report artifact
      │    └─ Open or append to GitHub issue (label: drift)
      │         ├─ Existing open drift issue? → add comment with new diff
      │         └─ No existing issue? → create new issue with label 'drift'
      │
      └─ [if drift_found=false]
           └─ Find open drift issue created by github-actions[bot]
                ├─ Found? → comment "✅ Drift resolved as of <date>" + close issue
                └─ Not found? → no-op
```

---

### 11. Weekly branch cleanup (Sundays 02:00 UTC)

**Trigger:** `schedule` cron `0 2 * * 0` OR `workflow_dispatch` with optional `dry_run` and `days_old`

```
Sunday 02:00 UTC (or manual dispatch)
      │
      ▼
cleanup-branches.yml
  timeout: 15 min
  permissions: contents:write, pull-requests:read
      │
      └─ Delete stale and merged branches (github-script)
           │
           ├─ DRY_RUN = github.event.inputs.dry_run || 'false'
           │    ├─ Schedule trigger: dry_run defaults to 'false' → LIVE deletion
           │    └─ Manual dispatch: dry_run defaults to 'true' → safe preview
           │
           ├─ PROTECTED (never deleted): main, master, develop, qa, stage,
           │    pre-prod-validation, deployments-ledger, release/*, hotfix/*, v*.*.*
           │    + any branch with GitHub branch protection rules
           │
           ├─ For each non-protected branch:
           │    ├─ Fetch last commit date via GitHub API
           │    ├─ Check for associated merged/closed PRs
           │    └─ Delete if: (merged PR OR closed PR OR stale) AND older than DAYS_OLD (default: 60)
           │
           └─ Write summary table: deleted / kept / skipped
```

---

### 12. Manual first-run baseline

**Trigger:** `workflow_dispatch` with `branch` input

```
Manual: Actions → First-Run Baseline → Run workflow
  input: branch (name of the branch to baseline)
      │
      ▼
first-run-baseline.yml
  timeout: 10 min
  permissions: contents:read
      │
      ├─ Checkout the specified branch (branch input via env var — injection-safe)
      └─ Record baseline to step summary (all lines correctly redirected to $GITHUB_STEP_SUMMARY)
           ## Baseline established
           Branch: <branch>
           Commit: <sha>
           Subsequent runs use this commit as delta start point.
```

---

## Workflow reference — every file explained

### Reusable workflows (called by environment workflows, not triggered directly)

| File | Purpose | Called by |
|---|---|---|
| `_reusable-validate.yml` | Delta generation, dynamic test selection, rollback snapshot, dry-run validation. Returns `validation_id`, `nothing_to_deploy`. | `sfdev`, `sfqa`, `sfstage`, `sfpreprodvalidation`, `sfprod` |
| `_reusable-deploy.yml` | Quick-deploy (or full-deploy fallback), pre/post Apex scripts, deployment ledger. | `sfdev`, `sfqa`, `sfstage`, `sfprod` |

### Environment caller workflows (triggered by push/dispatch)

| File | Branch | Test level | Deploys? | Notes |
|---|---|---|---|---|
| `sfdev.yml` | `develop` | RunSpecifiedTests | Yes | Dynamic test list |
| `sfqa.yml` | `qa` | RunLocalTests | Yes | Also receives cherry-picks |
| `sfstage.yml` | `stage` | RunLocalTests | Yes | |
| `sfpreprodvalidation.yml` | `pre-prod-validation` | RunAllTestsInOrg | No | Validate-only gate |
| `sfprod.yml` | `main` | RunAllTestsInOrg | Yes | Manual approval required |

### Utility workflows

| File | Trigger | What it does |
|---|---|---|
| `salesforce-pr-review.yml` | PR to `develop`/`qa`/`stage`/`main` | Two-layer review: static rules + Claude AI. Skips Dependabot PRs. `continue-on-error` so review crash never blocks merge. |
| `cherry-pick-workflow.yml` | PR merged to `develop` (title starts "Cherry") | Cherry-picks to `qa` using `merge_commit_sha`. Handles both regular merge (uses `-m 1`) and squash merge. |
| `rollback.yml` | Manual dispatch | Restores environment from pre-deploy snapshot artifact. |
| `drift-detection.yml` | Weekly schedule + manual | Org vs `main` diff. Auto-opens drift issue; auto-closes it when drift resolves. |
| `cleanup-branches.yml` | Weekly schedule + manual | Deletes merged/stale branches. Schedule runs live; manual dispatch defaults to dry-run. |
| `first-run-baseline.yml` | Manual dispatch | Creates a successful run record so delta logic has a start commit. |

---

## How the AI review agent works

### When it runs

On every PR opened or updated against `develop`, `qa`, `stage`, or `main`. Skips Dependabot PRs automatically. Does **not** run on direct pushes — it is a code-review tool, not a deployment guard.

### Two layers, one review

**Layer 1 — Static rules** (`.github/scripts/rules/`)

Deterministic pattern-matching, 30+ rules. Fires regardless of API key:

| Rule | What it catches |
|---|---|
| SF-APEX-001 | SOQL inside a for/while loop |
| SF-APEX-002 | DML inside a for/while loop |
| SF-APEX-004 | Silent exception swallowing (catch that only logs) |
| SF-APEX-005 | SOQL without `WITH USER_MODE` / `WITH SECURITY_ENFORCED` |
| SF-APEX-006 | `@AuraEnabled` method without try/catch |
| SF-TRIG-001 | Too much logic in trigger body |
| SF-TRIG-002/003 | SOQL/DML in trigger body |
| SF-LWC-001 | Hardcoded URL |
| SF-LWC-002 | Imperative Apex `.then` with no `.catch` |
| SF-LWC-003 | `document.querySelector` (use `template.querySelector`) |
| SF-SEC-001 | `global` access modifier overuse |
| SF-SEC-002 | Class without explicit `with sharing` / `without sharing` |
| SF-META-001 | API version below team minimum |
| SF-META-002 | Destructive change (file deletion) |

**Layer 2 — Claude Sonnet AI agent** (`.github/scripts/ai-review.js`)

Read-only — never writes code. Catches things pattern-matching cannot:

| Category | What it spots |
|---|---|
| CRUD/FLS | `@AuraEnabled` method missing `Schema.sObjectType.X.isCreateable()` checks |
| Sharing | `without sharing` on a class that exposes user-facing data |
| Async | `@future` calling another `@future`; Queueable not chained correctly |
| Trigger ↔ Flow | Record-triggered flow on same object/event as a trigger |
| Cross-file impact | Field rename breaking Apex in other files |
| Method signatures | Public method param change breaking callers elsewhere in the repo |
| LWC reactivity | Stale state between `@wire` and imperative calls; missing error path |
| Flow null-safety | Get Records → field reference without "no records" branch |

The AI layer also automatically collects **context files** — if your PR changes `AccountTrigger.cls`, the agent also receives other Account triggers, Account flows, and `Account.object-meta.xml`. It reasons over cross-file blast radius, not just the diff.

### Cost guards (in order of impact)

| # | Guard | Effect |
|---|---|---|
| 1 | Skip non-logic PRs | XML-only PRs never call the API — $0.00 |
| 2 | Diff-only for metadata files | Non-logic files send diff only, not full content |
| 3 | Hard input cap (~12,500 tokens) | Context files dropped until request fits |
| 4 | Output cap (`max_tokens: 2048`) | Caps response at ~15 findings |
| 5 | Context file limit (max 8) | Never sees more than 8 related files regardless of budget |

### What a finding looks like

The bot posts a single GitHub PR review with inline comments on diff lines:

```
🔴 SF-APEX-001 — SOQL query inside a loop. Move the query outside
the loop and process results in bulk.

Suggestion: Query before the loop, then iterate over the result set.
```

`🔴` high = REQUEST_CHANGES (PR cannot merge until fixed or dismissed).  
`🟡` medium / `🔵` low = COMMENT only — informational, does not block merge.

### What it deliberately does NOT do

- Never writes or suggests code (descriptions only)
- Never requests changes for low/medium findings
- Never re-reviews on its own — push a new commit to trigger a new review
- Never sees secrets

---

## Architectural improvements

### 1. Concurrency groups on every workflow

Every workflow now declares a `concurrency:` group. If two pushes arrive on the same branch before the first run completes:

- **Deploy and rollback workflows:** `cancel-in-progress: false` — the second run queues, never cancels a deploy mid-flight (which could leave the org in a partial state).
- **PR review and cherry-pick:** `cancel-in-progress: true` — stale review runs are superseded by the latest push.

### 2. Timeout guards on every job

| Job type | Timeout |
|---|---|
| Deploy jobs | 90 min |
| Validate jobs | 60 min |
| Drift detection | 30 min |
| Cleanup / cherry-pick / PR review | 15 min |
| First-run baseline | 10 min |

Prevents hung runners from consuming all available CI minutes.

### 3. Shell injection hardening

All user-controlled or context-controlled values (`github.actor`, `inputs.commit_hash`, `github.ref_name`, `inputs.test_level`, `github.event.pull_request.merge_commit_sha`, etc.) are passed through `env:` blocks and referenced as `$ENV_VAR` in shell — never interpolated directly as `${{ }}` inside `run:` steps. This prevents code injection via crafted branch names, PR titles, or usernames.

### 4. Quick-deploy with validation ID handoff

The validate job captures the validation deployment ID (valid 10 days). The deploy job uses `sf project deploy quick --job-id <id>`, skipping the Apex test re-run:

- Validate (once): full Apex run, 25–40 min
- Deploy (immediate): quick-deploy, 3–8 min

Same correctness guarantee, ~70% less wall time on the deploy.

### 5. Pre-deploy snapshot + rollback

Before deploying, the validate job retrieves the **current** state of every metadata file in the delta and uploads it as a workflow artifact (`rollback-snapshot-<env>-<run_id>`, retained 30 days). Emergency rollback re-deploys this snapshot. New components cannot be auto-rolled back (the workflow detects this and explains it).

### 6. Drift detection with auto-open and auto-close

Weekly job diffs prod metadata against `main`. Auto-opens a GitHub issue if drift is found. If the following week shows no drift, the issue is **automatically closed** with a "drift resolved" comment — no manual housekeeping required.

### 7. Deployment ledger

Every deploy writes a JSON audit record (timestamp, actor, commit SHA, deploy ID, validation ID, test level, outcome) to the `deployments-ledger` git branch. Full audit trail queryable with `git log deployments-ledger`.

### 8. Cherry-pick automation with merge/squash detection

When a PR merged to `develop` has a title starting with "Cherry", its commit is automatically cherry-picked to `qa`, which in turn triggers the QA deploy pipeline. The workflow correctly handles both merge commits (uses `git cherry-pick -m 1`) and squash-merge commits (single-parent, uses direct `git cherry-pick`).

### 9. Production guardrails

- `RunAllTestsInOrg` mandatory for prod (hardcoded in `sfprod.yml`)
- Manual approval gate on the `sfprod` GitHub environment
- Quick-deploy runs only after manual approval
- Branch protection on `main` restricts pushes

### 10. `actions: read` permission on all validate callers

The validate workflow uses the GitHub CLI (`gh run list`) to find the last successful run for delta calculation. This requires `actions: read`. All five caller workflows now declare this permission, ensuring the `gh` command works even in repositories with restricted default token permissions.

---

## Operational runbooks

### "I need to deploy to prod"

1. Open PR from feature branch → `develop`
2. Wait for **PR review bot** to post findings; address any 🔴 issues
3. Get human approval, merge to `develop` — `sfdev.yml` runs automatically
4. Open PR `develop` → `qa`, merge — `sfqa.yml` runs
5. Open PR `qa` → `stage`, merge — `sfstage.yml` runs
6. Open PR `stage` → `pre-prod-validation`, merge — `sfpreprodvalidation.yml` validates only
7. Open PR `pre-prod-validation` → `main`
8. On merge, `sfprod.yml` runs validate (RunAllTestsInOrg); **deploy pauses for manual approval**
9. Approver clicks **Review deployments** → **Approve** in the workflow run
10. Quick-deploy completes; ledger entry written to `deployments-ledger`

### "I need to cherry-pick a hotfix to QA immediately"

1. Create your PR targeting `develop` and give it a title starting with "Cherry" (e.g., `Cherry: Fix null pointer in AccountController`)
2. Merge the PR
3. The `cherry-pick-workflow.yml` fires automatically and pushes the commit to `qa`
4. `sfqa.yml` fires automatically — the fix is deployed to QA without any manual step

### "Prod broke — get me back"

1. Find the bad workflow run: **Actions** → **SF Prod** → bad run → copy the **Run ID**
2. **Actions** → **Rollback Deployment** → **Run workflow**
3. Environment: `sfprod`, Run ID: the one you copied, Confirm: type `ROLLBACK`
4. For speed: set `test_level` to `NoTestRun` (emergency speed); leave as `RunLocalTests` for safety
5. Approve the `sfprod` environment gate
6. Snapshot is redeployed; the rollback summary appears in the step summary

### "Drift was detected"

1. Check the auto-opened drift issue — it contains the first 200 lines of diff and a link to the full artifact
2. For each drifted item: either recreate the change in git (PR through the normal flow) or revert it in the org directly
3. Wait for the next Monday's drift detection run — it will auto-close the issue if no drift remains
4. Or run the drift detection workflow manually to check immediately

### "I want to preview which branches will be cleaned up"

1. **Actions** → **Cleanup Stale Branches** → **Run workflow**
2. Set `dry_run` to `true` (the default for manual dispatch)
3. Review the summary table — it shows every branch that would be deleted and why
4. To run live: set `dry_run` to `false`

> Note: The scheduled Sunday run (`dry_run=false`) actually deletes branches. Protected branches (main, develop, qa, stage, release/*, hotfix/*, v*.*.*) are never touched.

### "Rotate JWT keys"

```bash
# Generate new pair
openssl genrsa -out server-new.key 2048
openssl req -new -key server-new.key -out server-new.csr -subj "/C=GB/O=YourCompany/CN=ci-integration"
openssl x509 -req -sha256 -days 730 -in server-new.csr -signkey server-new.key -out server-new.crt

# In Salesforce: each Connected App → Edit → upload server-new.crt → Save
# In GitHub: each environment → SF_JWT_KEY → Update with contents of server-new.key
# Verify: run sfdev.yml manually — if it passes, rotation is complete
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
- Dependabot PRs are intentionally skipped — this is expected behavior

**JWT auth fails with `OAUTH_APP_ACCESS_DENIED`**
- The integration user isn't pre-authorized on the Connected App. Manage → Manage Profiles or Permission Sets.

**JWT auth fails with `JWT validation failed`**
- The `SF_JWT_KEY` secret is missing the `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` lines, or has Windows line endings
- Re-paste the key. On macOS/Linux: `cat server.key | pbcopy`

**Quick-deploy fails with "validation ID expired"**
- Salesforce's 10-day window has passed. Re-run the validate workflow to get a fresh ID, or let deploy fall back to full deploy automatically.

**`No prior successful run found`**
- Run **First-Run Baseline** for that branch, then push again.

**AI layer is silently skipping**
- `ANTHROPIC_API_KEY not set — skipping AI review layer`: the secret isn't configured
- `no logic files changed — skipping (cost guard 1)`: the PR is XML-only — expected behavior

**Cherry-pick workflow fails with "Conflict"**
- The commit being cherry-picked conflicts with changes already on `qa`
- Resolve: manually cherry-pick locally with conflict resolution, then push to `qa`

**Cherry-pick workflow fails with "merge_commit_sha is empty"**
- Rare race condition where the PR close event fires before GitHub populates the merge SHA
- Re-run the workflow manually or re-open and re-close the PR

**Drift detection issues keep re-opening after I close them**
- The workflow only auto-closes issues it opened itself (author = `github-actions[bot]`) with the exact title `⚠️ Drift detected between Prod org and main`
- If you closed the issue manually and the drift is still present, the workflow will open a fresh one on the next run

**Scheduled cleanup is deleting branches I want to keep**
- Add branch name or pattern to the `PROTECTED_BRANCHES` or `PROTECTED_PATTERNS` list in `cleanup-branches.yml`
- Or add a GitHub branch protection rule — the workflow respects the GitHub API's protection rules

**Rollback says "Snapshot is empty"**
- The original deployment only created NEW components (no pre-existing metadata to snapshot)
- Use destructive changes to remove them, or restore manually from a backup

---

## Repository layout

```
.github/
├── workflows/
│   ├── _reusable-validate.yml        # shared validate logic (timeout: 60min, actions:read)
│   ├── _reusable-deploy.yml          # shared deploy logic + ledger (timeout: 90min)
│   ├── sfdev.yml                     # develop → SF Dev (concurrency: deploy-sfdev)
│   ├── sfqa.yml                      # qa → SF QA (concurrency: deploy-sfqa)
│   ├── sfstage.yml                   # stage → SF Stage (concurrency: deploy-sfstage)
│   ├── sfprod.yml                    # main → SF Prod, manual approval (concurrency: deploy-sfprod)
│   ├── sfpreprodvalidation.yml       # pre-prod-validation → validate-only (concurrency: deploy-sfprod-validation)
│   ├── salesforce-pr-review.yml      # PR review bot (concurrency: pr-review-<PR#>, skip Dependabot)
│   ├── cherry-pick-workflow.yml      # develop Cherry-prefixed PRs → qa (merge/squash aware)
│   ├── rollback.yml                  # manual rollback with test_level choice (concurrency: rollback-<env>)
│   ├── drift-detection.yml           # weekly org-vs-main diff with auto-open + auto-close
│   ├── first-run-baseline.yml        # one-time baseline per branch
│   └── cleanup-branches.yml          # weekly live deletion + manual dry-run
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
scripts/
├── apex/hello.apex                   # sample anonymous Apex (SF: Execute Anonymous Apex)
├── soql/account.soql                 # sample SOQL query (SELECT Id, Name FROM Account LIMIT 200)
└── Bash/DeleteBranches.sh            # local branch cleanup utility (cross-platform, protected-branch-safe)
deployments/                          # ledger entries (auto-committed to deployments-ledger branch)
sfdx-project.json
Jenkinsfile                           # stub (pipeline uses GitHub Actions; Jenkinsfile is a legacy placeholder)
```

---

## Credits and license

Static rule design and the validate→quick-deploy pattern are adapted from common Salesforce DevOps practices. The AI review layer architecture (read-only, two-layer, cost-guarded) is inspired by the [`gabrielolv/salesforce-devops-pipeline`](https://github.com/gabrielolv/salesforce-devops-pipeline) project and adapted for this repo's needs.
