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
