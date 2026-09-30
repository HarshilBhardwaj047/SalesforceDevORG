# Dry Run Log — Branching & Development Workflow

This log records a live dry run of the "Standard Feature" flow described in
[`docs/WORKFLOW.md`](./WORKFLOW.md), executed step-by-step against the real
repository to verify the documented process works as written.

**Scope:** `feature/*` branch → PR → `develop`. The run stops at the open PR
(does not merge), so it does **not** exercise the `qa`/`stage`/`master`
promotion stages or trigger any real Salesforce deployment. Those stages are
noted as "not exercised" below.

**Date:** 2026-09-30

---

## Step 0 — Fresh pull of the repo

```bash
git fetch --all --prune
git checkout master
git pull --ff-only origin master
```

Result: fast-forwarded local `master` from `1849d36` → `fe682fd`
(6 commits, includes the merge of PR #30 which added `docs/WORKFLOW.md`).
Fetch also pruned ~20 stale remote branches that had already been deleted
upstream (leftover test/sync branches from prior cherry-pick experiments).

---

## Step 1 — Branch off develop

Per WORKFLOW.md §4 "Standard Feature":

```bash
git checkout -b feature/DRYRUN-01-workflow-walkthrough origin/develop
```

Result: branch created from `origin/develop`, tracking it. Note: `develop`'s
copy of `scripts/apex/hello.apex` differs slightly from `master`'s (comment
says `SFDX: Execute Anonymous Apex...` vs `master`'s `SF: Execute Anonymous
Apex...`) — a small existing drift between branches, unrelated to this dry
run.

---

## Step 2 — Develop & commit locally

Per WORKFLOW.md §4, made a trivial, reversible change: appended a comment
line to `scripts/apex/hello.apex` (no behavior change) and added this log
file itself.

```bash
git add scripts/apex/hello.apex docs/DRY_RUN_LOG.md
git commit -m "test: dry run of branching workflow (no-op comment, safe to discard)"
```

Result: commit `0c3642b` — 2 files changed (`docs/DRY_RUN_LOG.md` new,
`scripts/apex/hello.apex` modified).

---

## Step 3 — Push and open PR → develop

```bash
git push -u origin feature/DRYRUN-01-workflow-walkthrough
gh pr create --base develop \
  --title "test: dry run of branching workflow (do not merge)" \
  --body "Dry run of docs/WORKFLOW.md Standard Feature flow. Trivial, reversible change. Verifying PR review bot fires. Will be closed without merging."
```

Result: PR **[#31](https://github.com/HarshilBhardwaj047/SalesforceDevORG/pull/31)**
opened, `feature/DRYRUN-01-workflow-walkthrough` → `develop`.

---

## Step 4 — PR triggers observed

WORKFLOW.md §4 step 4 claims the PR triggers "Salesforce PR Review" and a
validation deploy against the dev scratch org. Observed:

| Expected (per docs) | Observed |
|---|---|
| `Salesforce PR Review` fires on PR open | ✅ Fired within ~3s of PR creation (`gh run list`), completed in 15s, conclusion `success` |
| Static + AI review layers run | ✅ Bot posted a review comment: `✅ Salesforce PR Review — No issues found by static or AI layers.` (expected — the only change is a comment line in an `.apex` script, no logic files) |
| Review posted as a GitHub PR review | ✅ Confirmed via `gh pr view 31 --json reviews` — review authored by `github-actions[bot]`, state `COMMENTED` |
| Runner annotations | Informational only: Node.js 20 deprecation notice, `ubuntu-latest` → Ubuntu 26 migration notice (unrelated to this repo's logic, GitHub-runner-level notices) |

**Not observed / out of scope for this dry run:** a separate "validation deploy
against dev scratch org" workflow on the PR itself — per README.md's trigger
map, dev/QA/stage/prod deploys are triggered by **pushes to their respective
branches** (`develop`, `qa`, `stage`, `main`/`master`), not by opening a PR.
The only PR-triggered workflow is `salesforce-pr-review.yml`. This is a minor
discrepancy between WORKFLOW.md's wording ("Validation deploy against dev
scratch org" listed as a PR trigger) and the actual trigger map in README.md
— worth flagging for a doc fix.

---

## Step 5 — Stopping point (by design)

Per the agreed dry-run scope, this run **stops here** — the PR is left open,
unmerged. Steps not exercised:

- Merge to `develop` (would trigger real `sfdev.yml` deploy to the Dev org)
- Cherry-pick flow to `qa` (only triggers on merge with a `Cherry`-prefixed title)
- PR `qa` → `stage`, `stage` → `master`
- Hotfix flow
- Branch protection enforcement (not testable without attempting a disallowed push)

---

## Summary

| WORKFLOW.md claim | Verified? |
|---|---|
| `feature/*` branches off `develop` | ✅ |
| PR to `develop` opens cleanly via `gh pr create --base develop` | ✅ |
| PR triggers `Salesforce PR Review` automatically | ✅ |
| Review bot posts a single consolidated review | ✅ |
| Comment-only Apex change → clean pass, no findings | ✅ |
| "Validation deploy against dev scratch org" on PR (§4 step 4) | ⚠️ Not observed — deploys are branch-push-triggered per README.md's trigger map, not PR-triggered. Doc wording is slightly misleading. |

**Artifacts:** branch `feature/DRYRUN-01-workflow-walkthrough`, PR #31,
workflow run [36693320631](https://github.com/HarshilBhardwaj047/SalesforceDevORG/actions/runs/36693320631).

**Cleanup:** Close PR #31 without merging, then delete the branch locally and
on origin:

```bash
gh pr close 31
git checkout master
git branch -D feature/DRYRUN-01-workflow-walkthrough
git push origin --delete feature/DRYRUN-01-workflow-walkthrough
```
