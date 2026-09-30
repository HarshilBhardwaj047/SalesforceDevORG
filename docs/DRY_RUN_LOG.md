# Dry Run Log — Branching & Development Workflow

This log records a live dry run of the "Standard Feature" flow described in
[`docs/WORKFLOW.md`](./WORKFLOW.md), executed step-by-step against the real
repository to verify the documented process works as written.

**Scope:** `feature/*` branch → PR → `develop`. The run stopped at the open
PR (no merge), so it does **not** exercise the `qa`/`stage`/`master`
promotion stages or trigger any real Salesforce deployment.

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
Fetch also pruned ~20 stale remote branches already deleted upstream
(leftover test/sync branches from prior cherry-pick experiments).

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
| `Salesforce PR Review` fires on PR open | ✅ Fired within ~3s of PR creation, completed in 15s, conclusion `success` |
| Static + AI review layers run | ✅ Bot posted a review: `✅ Salesforce PR Review — No issues found by static or AI layers.` (expected — the only change is a comment line in an `.apex` script, no logic files) |
| Review posted as a GitHub PR review | ✅ Confirmed via `gh pr view 31 --json reviews` — review authored by `github-actions[bot]`, state `COMMENTED` |
| Push a new commit → new review fires | ✅ Second push (adding this log's final section) triggered a second `Salesforce PR Review` run via the `synchronize` event, matching README.md's "push a new commit to trigger a new review" |
| Runner annotations | Informational only: Node.js 20 deprecation notice, `ubuntu-latest` → Ubuntu 26 migration notice (GitHub-runner-level, unrelated to repo logic) |

**Not observed / out of scope for this dry run:** a separate "validation
deploy against dev scratch org" workflow firing on the PR itself — per
README.md's trigger map, dev/QA/stage/prod deploys are triggered by **pushes
to their respective branches** (`develop`, `qa`, `stage`, `main`/`master`),
not by opening a PR. The only PR-triggered workflow is
`salesforce-pr-review.yml`. This is a minor discrepancy between
WORKFLOW.md's wording ("Validation deploy against dev scratch org" listed as
a PR trigger) and the actual trigger map in README.md — worth a doc fix.

---

## Step 5 — Stopping point (by design)

Per the agreed dry-run scope, steps not exercised:

- Merge to `develop` (would trigger real `sfdev.yml` deploy to the Dev org)
- Cherry-pick flow to `qa` (only triggers on merge with a `Cherry`-prefixed title)
- PR `qa` → `stage`, `stage` → `master`
- Hotfix flow
- Branch protection enforcement (not testable without attempting a disallowed push)

---

## Cleanup performed

```bash
gh pr close 31 --comment "Dry run of docs/WORKFLOW.md complete — PR review bot confirmed working as documented. Closing without merge per dry-run scope."
git checkout master
git branch -D feature/DRYRUN-01-workflow-walkthrough
git push origin --delete feature/DRYRUN-01-workflow-walkthrough
```

PR #31 closed without merging. Scratch branch deleted locally and on origin.
Repo left on `master`, clean.

---

## Summary

| WORKFLOW.md claim | Verified? |
|---|---|
| `feature/*` branches off `develop` | ✅ |
| PR to `develop` opens cleanly via `gh pr create --base develop` | ✅ |
| PR triggers `Salesforce PR Review` automatically | ✅ |
| Review bot posts a single consolidated review | ✅ |
| Comment-only Apex change → clean pass, no findings | ✅ |
| New commit on the PR re-triggers the review | ✅ |
| "Validation deploy against dev scratch org" on PR (§4 step 4) | ⚠️ Not observed — deploys are branch-push-triggered per README.md's trigger map, not PR-triggered. Doc wording is slightly misleading. |

**Artifacts (now closed/deleted):** branch
`feature/DRYRUN-01-workflow-walkthrough`, PR
[#31](https://github.com/HarshilBhardwaj047/SalesforceDevORG/pull/31), workflow run
[36693320631](https://github.com/HarshilBhardwaj047/SalesforceDevORG/actions/runs/36693320631).

This file (`docs/DRY_RUN_LOG.md`) exists only in the local working tree — it
was never merged (the PR was closed, not merged). Commit it on a real
branch/PR if you want it kept in the repo's history.

---

## Dry Run 4 — Trigger / LWC / metadata static rules (PR #35, closed unmerged)

Planted 8 violations across SF-TRIG-001/002/003, SF-META-001/002,
SF-LWC-001/002/003 in a new trigger + LWC component + a deleted class.
Static engine reported **7 findings**; AI layer failed with the same
credit-exhaustion 400 as issue #33. **5 of 7 targeted rules fired
correctly** (SF-TRIG-001/003, SF-META-001, SF-LWC-001/002/003). Two did
not fire, both root-caused to real code bugs, filed as
[issue #36](https://github.com/HarshilBhardwaj047/SalesforceDevORG/issues/36):
- **SF-META-002** never fires — `diffParser.js`'s `path: f.to || f.from`
  always resolves to `/dev/null` for deleted files (parse-diff's `+++
  /dev/null` convention), so `checkDeleted()`'s extension check never
  matches.
- **SF-TRIG-002** misses multi-line `[SELECT...]` blocks — its regex only
  matches when `[` and `SELECT` are on the same line, but this repo's own
  convention (see `AccountController.cls`) always splits them.

PR closed, branch deleted. Full violation table and cleanup commands
mirror Dry Runs 1–3's methodology (see PR #35 diff on GitHub for exact
file contents).

---

## Dry Run 5 — Real Cherry-prefixed PR merge to develop (PR #37, MERGED)

**Scope change from Dry Runs 1–4:** with explicit user approval ("there
are no org connections so nothing will be deployed"), this PR was
actually merged, to observe the real cherry-pick → qa → sfqa.yml chain
end to end.

Steps: branched `feature/DRYRUN-05-cherry-pick-test` off `develop`, made a
trivial comment-only change to `scripts/apex/hello.apex`, opened PR #37
titled `Cherry: dry run 5 — verify cherry-pick-workflow promotion to qa`,
review bot passed (no findings), merged with a real merge commit
(`e985b02`).

| Step | Expected (WORKFLOW.md §5) | Observed |
|---|---|---|
| Merge triggers `sfdev.yml` on `develop` | ✅ deploy attempt | ✅ Fired, but **failed** — see below |
| Merge triggers `cherry-pick-workflow.yml` (Cherry-prefixed) | ✅ cherry-pick to `qa` | ✅ **Fully succeeded** — cherry-picked `e985b02` onto `qa`, pushed `38053a2..5b746ab` |
| Push to `qa` triggers `sfqa.yml` | ✅ deploy attempt | ❌ **Never fired at all** — no run, ever |

Two new, previously-undiscovered real bugs found and filed:

- **[Issue #38](https://github.com/HarshilBhardwaj047/SalesforceDevORG/issues/38)** — `sfqa.yml` never fires after a cherry-pick, because
  `cherry-pick-workflow.yml` pushes to `qa` using `secrets.GITHUB_TOKEN`,
  and GitHub Actions does not let `GITHUB_TOKEN`-authored pushes trigger
  other workflows (anti-recursion guard). The entire documented
  `Cherry PR → qa → sfqa.yml` promotion chain is silently a no-op for the
  QA deploy step, even though the cherry-pick itself works perfectly.
- **[Issue #39](https://github.com/HarshilBhardwaj047/SalesforceDevORG/issues/39)** — `sfdev.yml`'s validate job failed with
  `Unable to process file command 'output' successfully` /
  `Invalid format '0 components across 0'`. Root cause: (a)
  `_reusable-validate.yml`'s "no prior successful run" fallback computes
  `git merge-base HEAD origin/develop`, which trivially equals `HEAD`
  itself on a push-to-develop run, so the delta is always self-vs-self
  (guaranteed empty) on every first run; (b) `generate-delta/action.yml`'s
  `grep -c ... || echo 0` bug — `grep -c` prints `0` and still exits 1 on
  zero matches, so `|| echo 0` fires anyway and appends a second `0` line,
  producing a two-line value that corrupts the `$GITHUB_OUTPUT` write.
  Together these mean the deploy pipeline can **never reach a first
  successful run** through this fallback path — a structural deadlock,
  not a flaky failure, and likely the explanation for the failure streak
  visible back to 2026-06-20.

Cleanup: PR #37 is merged (intentionally, not closed-unmerged like Dry
Runs 1–4). Scratch branch deleted locally and on origin
(`feature/DRYRUN-05-cherry-pick-test`). `develop` and `qa` both carry the
trivial comment-only change permanently — harmless, matches the pattern
of other real `test/cherry-*` branches already merged into this repo's
history from prior experiments (see `qa`'s commit log).

---

## Cumulative status after Dry Runs 1–5

| Capability | Status |
|---|---|
| `salesforce-pr-review.yml` (PR open/sync trigger) | ✅ works |
| Static rules: Apex/security/trigger/LWC/metadata (13 of 15 rule IDs) | ✅ verified correct |
| Static rules: SF-META-002, SF-TRIG-002 | ❌ real bugs — issue #36 |
| AI layer (Claude Sonnet review) | ❌ down — credit exhausted, issue #33 |
| `cleanup-branches.yml` (dry-run mode) | ✅ works |
| `first-run-baseline.yml` | ⚠️ runs, but records the wrong SHA for non-default branches (`github.sha` bug, folded into issue #39's writeup) |
| `drift-detection.yml` | ⚠️ fails as expected — no SF org credentials configured |
| `cherry-pick-workflow.yml` | ✅ **works correctly** — cherry-picks and pushes to `qa` cleanly |
| `sfdev.yml` / `sfqa.yml` / `sfstage.yml` / `sfprod.yml` (real deploy pipeline) | ❌ **structurally cannot succeed** — issues #38 (qa push never triggers sfqa.yml) and #39 (first-run delta computation deadlock) |
| `rollback.yml` | ⏳ not tested — needs a prior successful deploy snapshot, which cannot exist given #39 |
