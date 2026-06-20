# Branching & Development Workflow

This document is the authoritative reference for how code moves through the
`SalesforceDevORG` repository — from a developer's local machine to production.

---

## Table of Contents

1. [Branch Map](#1-branch-map)
2. [Environment Pipeline](#2-environment-pipeline)
3. [Branch Definitions & Rules](#3-branch-definitions--rules)
4. [Day-to-Day Development Flow](#4-day-to-day-development-flow)
5. [Cherry-pick Workflow (Selective Promotion)](#5-cherry-pick-workflow-selective-promotion)
6. [Hotfix Flow](#6-hotfix-flow)
7. [Choosing Between Option A and Option B](#7-choosing-between-option-a-and-option-b)
8. [Branch Protection Rules](#8-branch-protection-rules)
9. [Critical Constraints & Known Gotchas](#9-critical-constraints--known-gotchas)
10. [CI/CD Workflow Summary](#10-cicd-workflow-summary)
11. [Glossary](#11-glossary)

---

## 1. Branch Map

```
feature/* ─────────────────────────────────────────────────────┐
hotfix/*  ──────────────────────────────────────────────────┐  │
                                                            │  │
                                                            ▼  ▼
master ◄─── stage ◄─── qa ◄─── develop ◄─── feature/*
                                  │
                                  └── [Cherry PR] ──► qa
                                        (selective promotion)
```

| Branch | Maps to Environment | Deployed by |
|--------|--------------------|----|
| `master` | Production | `sfprod.yml` on merge |
| `stage` | Staging / Pre-prod | `sfstage.yml` on merge |
| `qa` | QA | `sfqa.yml` on push |
| `develop` | Dev sandbox | `sfdev.yml` on push |
| `feature/*` | Developer's scratch org | manual / PR validation |
| `hotfix/*` | Patch branch | manual merge to `master` + `develop` |

---

## 2. Environment Pipeline

Code always flows in one direction:

```
feature/* (or hotfix/*)
      │
      │  PR → develop
      ▼
   develop          ← all active development lands here
      │
      │  automatic (linear) OR Cherry-pick PR (selective)
      ▼
     qa             ← QA testing environment
      │
      │  PR → stage (manual promotion after QA sign-off)
      ▼
    stage           ← pre-production / UAT
      │
      │  PR → master (manual promotion after UAT sign-off)
      ▼
   master           ← production
```

There are **two supported strategies** for how `develop` promotes to `qa`.
See [Section 7](#7-choosing-between-option-a-and-option-b) for how to choose.

---

## 3. Branch Definitions & Rules

### `master` — Production

- Represents what is live in the production Salesforce org.
- **No direct commits.** All changes arrive via PR from `stage`.
- Merging to `master` triggers `sfprod.yml` (Salesforce production deployment).
- Tag every merge with a version: `v1.2.3`.

### `stage` — Staging / Pre-prod

- Represents what is ready for UAT sign-off.
- **No direct commits.** All changes arrive via PR from `qa`.
- Merging to `stage` triggers `sfstage.yml`.

### `qa` — QA Environment

- Represents what is currently under QA testing.
- **No direct commits from developers.** Code arrives only via:
  - The automated cherry-pick workflow (Option A), OR
  - An automated linear merge from `develop` (Option B).
- The Actions bot is the only permitted pusher (enforce via branch protection).
- Merging or pushing to `qa` triggers `sfqa.yml`.

### `develop` — Integration / Dev Sandbox

- The main integration branch where all feature work lands.
- **No direct commits.** All changes arrive via PR from `feature/*`.
- Merging to `develop` triggers `sfdev.yml`.
- Source of truth for "what is built and tested."

### `feature/*` — Feature Branches

- Naming: `feature/<ticket-id>-short-description`
  Example: `feature/SF-42-account-search`
- Branch off `develop`.
- Delete after PR merges.
- PR title should start with `Cherry` if the change needs to be selectively
  promoted to `qa` ahead of the rest of `develop`.

### `hotfix/*` — Hotfix Branches

- Naming: `hotfix/<ticket-id>-short-description`
  Example: `hotfix/SF-99-fix-null-account`
- Branch off `master` (not `develop`).
- Must be merged into **both** `master` and `develop` (via separate PRs).
- Use when a production bug needs fixing immediately, bypassing the normal queue.

---

## 4. Day-to-Day Development Flow

### Standard Feature

```
1. Branch off develop
   git checkout -b feature/SF-42-account-search origin/develop

2. Develop & commit locally
   git commit -m "feat: add account search endpoint"

3. Push and open PR → develop
   git push origin feature/SF-42-account-search
   gh pr create --base develop --title "feat: add account search endpoint"

4. PR triggers:
   - Salesforce PR Review (AI-assisted code review bot)
   - Validation deploy against dev scratch org

5. Get approval → merge to develop
   → sfdev.yml deploys to dev sandbox automatically

6. QA promotion happens via cherry-pick workflow (Option A)
   or automatic sync (Option B) — see Sections 5 & 7
```

### Cherry-prefixed Feature (selective promotion)

```
1. Same as above, but name your PR with the "Cherry" prefix:
   Title: "Cherry: add account search endpoint"

2. On merge to develop, the cherry-pick workflow automatically
   copies the change to qa.

3. All other (non-Cherry) PRs stay on develop until the next
   scheduled qa sync.
```

---

## 5. Cherry-pick Workflow (Selective Promotion)

### How it works

The workflow lives at `.github/workflows/cherry-pick-workflow.yml`.

**Trigger:** Any PR that is:

- Merged (not just closed)
- Targeting the `develop` branch
- Has a title starting with `Cherry`

**Action:** The workflow cherry-picks the PR's commit onto the `qa` branch
and pushes it.

### Workflow YAML (simplified)

```yaml
on:
  pull_request:
    types: [closed]
    branches:
      - develop

jobs:
  cherry_pick:
    if: |
      github.event.pull_request.merged == true
      && startsWith(github.event.pull_request.title, 'Cherry')
```

### The `develop~1` constraint (important)

> **The cherry-pick workflow works correctly as long as `qa` is kept at
> `develop~1` (one commit behind). Any time a non-Cherry PR merges into
> `develop` without also being applied to `qa`, the gap grows and Cherry
> PRs will conflict.**

This happens because the current workflow cherry-picks the **merge commit**
(`merge_commit_sha`). The diff for a merge commit is computed against the
first parent (`-m 1`), which is the state of `develop` at merge time. If
`qa` does not have all the same prior commits as `develop`, that diff
cannot apply cleanly.

#### The robust fix (recommended)

Replace `merge_commit_sha` with `head.sha` (the feature branch tip) and
drop the parent-count logic:

```yaml
# Change this env var in cherry-pick-workflow.yml:
env:
  HEAD_SHA: ${{ github.event.pull_request.head.sha }}
  TARGET_BRANCH: qa

# Simplify the cherry-pick step to:
git cherry-pick -x "$HEAD_SHA"
```

The feature branch's head commit is a single, self-contained diff of just
that feature's changes — it has no dependency on what `qa` currently
contains. The `develop~1` constraint disappears entirely.

### Visual flow

```
developer opens PR titled "Cherry: my feature"
            │
            ▼
    PR merges into develop
            │
            ▼
  cherry-pick-workflow.yml triggers
  (event: pull_request, type: closed, merged: true)
            │
            ▼
  workflow checks out repo, switches to qa branch
            │
            ▼
  git cherry-pick <commit> applied to qa
            │
            ▼
  git push origin qa
            │
            ▼
  sfqa.yml deploys to QA org automatically
```

---

## 6. Hotfix Flow

Use this when production is broken and the fix cannot wait for the normal
`feature → develop → qa → stage → master` pipeline.

```
1. Branch off master
   git checkout -b hotfix/SF-99-fix-null-account origin/master

2. Fix the bug, commit
   git commit -m "fix: handle null account in controller"

3. Open PR → master
   gh pr create --base master --title "fix: handle null account in controller"
   → get approval → merge to master
   → sfprod.yml deploys to production

4. Backport: open a second PR → develop
   gh pr create --base develop --title "fix: backport null account fix"
   → merge to develop so the fix is not lost in future releases

5. Delete the hotfix branch
   git push origin --delete hotfix/SF-99-fix-null-account
```

> **Important:** Do NOT open the hotfix PR against `develop` first. The
> production fix must land on `master` before it lands on `develop`,
> otherwise a subsequent `stage → master` promotion could overwrite it.

---

## 7. Choosing Between Option A and Option B

### Option A: Selective Promotion via Cherry-pick (current setup)

**Use this when:** Not every feature that lands on `develop` should
immediately appear in QA. You need to hold some changes back while
promoting others (e.g., fast-tracking a fix to QA while a half-finished
feature stays behind).

```
feature/* ──► develop   (all dev work, regardless of readiness)
                │
         [Cherry PR] ──► qa   (only selected features)
```

**Maintenance requirement:** Either apply the `head.sha` fix described in
Section 5, OR manually keep `qa` at `develop~1` after every non-Cherry
merge. Failing to do so causes conflicts on the next Cherry PR.

**Recovery when qa has fallen behind:**

```bash
# Find the commit just before the Cherry PR you want to land
git log --oneline origin/develop | head -10

# Force-reset qa to that commit
git push origin <commit-sha>:refs/heads/qa --force
```

---

### Option B: Linear Promotion Pipeline (simpler, recommended for most teams)

**Use this when:** Everything in `develop` should eventually reach QA.
Selective holds are handled by _not merging the feature to `develop` yet_,
not by filtering what goes to `qa` after the fact.

```
feature/*
    │  PR
    ▼
 develop ──auto-sync──► qa ──PR──► stage ──PR──► master
```

Replace the cherry-pick workflow with this simple auto-sync job:

```yaml
name: Sync develop to qa

on:
  push:
    branches:
      - develop

jobs:
  sync:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}
      - name: Merge develop into qa
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git checkout qa
          git merge origin/develop --no-edit -m "chore: auto-sync develop into qa"
          git push origin qa
```

**Advantages over Option A:**

- No `develop~1` constraint, no conflict risk from branch drift
- `qa` always reflects exactly what is in `develop`
- No special PR naming convention needed
- Simpler mental model for the whole team

**Trade-off:** You lose the ability to hold a feature in `develop` while
promoting other features to `qa`. If you need that, stay on Option A.

---

## 8. Branch Protection Rules

Configure in **GitHub → Settings → Branches** for each protected branch.

| Branch | Require PR | Approvals | Restrict who can push | Status checks |
|--------|------------|-----------|----------------------|---------------|
| `master` | yes | 1 | admins only | `sfprod.yml` validate |
| `stage` | yes | 1 | admins only | `sfstage.yml` validate |
| `qa` | yes | 0 | `github-actions[bot]` only | none |
| `develop` | yes | 1 | nobody directly | `Salesforce PR Review` |
| `feature/*` | no | — | branch owner | none |
| `hotfix/*` | no | — | branch owner | none |

> **The most important rule:** `qa` must only accept pushes from the
> Actions bot. This prevents developers from manually pushing to `qa`,
> which causes the branch to drift and breaks future cherry-picks (as
> observed during the E2E testing of this repo).

### Locking `qa` to Actions bot only (GitHub CLI)

```bash
gh api repos/HarshilBhardwaj047/SalesforceDevORG/branches/qa/protection \
  --method PUT \
  --field required_status_checks=null \
  --field enforce_admins=false \
  --field required_pull_request_reviews=null \
  --field 'restrictions={"users":[],"teams":[],"apps":["github-actions"]}'
```

---

## 9. Critical Constraints & Known Gotchas

### 1. Workflow YAML must be ASCII-only

GitHub Actions parses workflow YAML strictly. Unicode characters — curly
quotes (`'` `'`), em dashes (`—`), non-breaking spaces — cause a silent
**"workflow file issue"** error that prevents the `pull_request` trigger
from firing entirely. The file looks valid locally but GitHub rejects it
at parse time.

**Rule:** Never paste workflow YAML from a rich-text editor, Word, Notion,
or a rendered Markdown preview. Always write from a plain-text source.

**How to check:**

```bash
python3 -c "
with open('.github/workflows/cherry-pick-workflow.yml', 'rb') as f:
    data = f.read()
bad = [(i+1, hex(b)) for i, b in enumerate(data) if b > 127]
print('Non-ASCII found:', bad) if bad else print('Clean -- all ASCII')
"
```

---

### 2. GitHub reads the workflow file from the base branch at trigger time

When a `pull_request` event fires, GitHub reads the workflow file from the
**base branch** of the PR — not the head branch. This means:

- If `cherry-pick-workflow.yml` on `develop` is the old `A→B` version,
  it will not trigger even if `master` has the correct version.
- Every long-lived branch that acts as a PR base must have the same
  up-to-date workflow file.
- After updating the workflow, propagate it to all branches using the
  script in [Section 10](#10-cicd-workflow-summary).

---

### 3. Cherry-picking merge commits vs feature commits

| Approach | What gets cherry-picked | `qa` drift risk |
|----------|------------------------|-----------------|
| `merge_commit_sha` + `-m 1` (current) | Merge commit diff vs develop | **High** — fails if qa lags develop by even one commit |
| `head.sha` (recommended) | Feature branch tip | **None** — self-contained diff |

---

### 4. `qa` force-reset procedure

When `qa` has fallen too far behind `develop` and cherry-picks are
conflicting, reset `qa` to the correct baseline:

```bash
# Reset qa to the commit just before the Cherry PR you want to land
# (i.e., qa = develop at the point the Cherry PR was branched from)
git fetch origin
git push origin <target-sha>:refs/heads/qa --force
```

After this, all subsequent Cherry PRs will apply cleanly as long as `qa`
is not allowed to fall behind again.

---

## 10. CI/CD Workflow Summary

| Workflow file | Trigger | What it does |
|--------------|---------|-------------|
| `cherry-pick-workflow.yml` | PR merged to `develop` with `Cherry` prefix | Cherry-picks commit to `qa` |
| `sfdev.yml` | Push to `develop` | Validates + deploys to dev sandbox |
| `sfqa.yml` | Push to `qa` | Deploys to QA org |
| `sfstage.yml` | Push to `stage` | Deploys to staging org |
| `sfprod.yml` | Push to `master` | Deploys to production org |
| `sfpreprodvalidation.yml` | PR to `master` | Validates deployment before merge |
| `salesforce-pr-review.yml` | PR opened / updated | AI code review bot |
| `drift-detection.yml` | Scheduled | Detects config drift between orgs |
| `cleanup-branches.yml` | Scheduled | Deletes stale merged branches |
| `rollback.yml` | Manual dispatch | Rolls back a deployment |

### Propagating workflow changes to all branches

When `cherry-pick-workflow.yml` is updated on `develop`, push it to all
other long-lived branches so the trigger works correctly regardless of
which branch is used as a PR base:

```bash
WORKFLOW=$(git show origin/develop:.github/workflows/cherry-pick-workflow.yml)

for branch in main master stage qa HarshilBhardwaj047-patch-1 \
              HarshilBhardwaj047-patch-2 chore/pipeline-setup; do
  git checkout -b "sync/workflow-${branch//\//-}" "origin/$branch"
  printf '%s\n' "$WORKFLOW" > .github/workflows/cherry-pick-workflow.yml
  git add .github/workflows/cherry-pick-workflow.yml
  git diff --cached --quiet || \
    git commit -m "chore: sync cherry-pick workflow to canonical version"
  git push origin "HEAD:$branch"
  git checkout -
done
```

---

## 11. Glossary

| Term | Meaning |
|------|---------|
| **Cherry PR** | A PR whose title starts with `Cherry` — triggers automatic promotion to `qa` on merge |
| **develop~1** | The commit one step behind `develop` HEAD — the required state of `qa` when using merge-commit cherry-pick |
| **merge commit** | The commit GitHub creates when merging a PR via "Create a merge commit" — has 2 parents |
| **squash merge** | When GitHub squashes all commits in a PR into one before merging — produces a single-parent commit |
| **head.sha** | The tip commit of the feature branch — a self-contained diff of just that feature's changes |
| **Option A** | Selective promotion: only Cherry PRs reach `qa` automatically |
| **Option B** | Linear promotion: every push to `develop` automatically syncs to `qa` |
| **branch protection** | GitHub setting that enforces PR requirements, required reviews, and push restrictions on a branch |
| **workflow file issue** | GitHub Actions error when a workflow YAML contains non-ASCII characters or expression syntax errors — silently prevents triggers from firing |
