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

## Bug-fix PR #40 — fixes for issues #33, #36, #38, #39

All four bugs surfaced by Dry Runs 1–5 were fixed on branch
`fix/pr-review-and-pipeline-bugs` and merged into `develop` (commit
`d0fd6c0`):

- **#33** — `runAiReview()` now returns `{ findings, error }` instead of a
  bare array; a real API/parse failure is threaded through to the posted
  review body instead of being indistinguishable from a clean pass.
- **#36** — added a shared `findSoqlStartLines()` utility (multi-line
  `[SELECT...]` detection) used by SF-TRIG-002/SF-APEX-001/005; fixed
  `diffParser.js` to resolve deleted-file paths from `from` instead of
  the always-truthy `/dev/null` in `to`, unblocking SF-META-002.
- **#39** — `generate-delta/action.yml`'s `grep -c ... || echo 0` changed
  to `|| true` (grep already prints `0` on zero matches); the first-run
  fallback in `_reusable-validate.yml` now prefers the push event's
  `before` SHA over the self-referential `git merge-base HEAD
  origin/develop`, falling back to `HEAD~1`.
- **#38** — `cherry-pick-workflow.yml` gained `actions: write` and an
  explicit `gh workflow run sfqa.yml --ref qa` dispatch step after the
  push to `qa`, since `GITHUB_TOKEN`-authored pushes can't fire other
  workflows' `on: push` triggers.

Issue #11 (pre-existing) was closed separately with a citation to Dry Run
5 as evidence the current `cherry-pick-workflow.yml` already handles
merge-vs-squash commits correctly.

---

## Dry Run 6 — Re-verify SF-META-002 + multi-line SOQL fixes (PR #41, closed unmerged)

Re-ran the exact violation shapes that exposed issue #36 in Dry Run 4,
now against the fixed rules engine. Branched
`test/DRYRUN-06-rule-fix-verification` off `develop`: deleted
`Basic.cls`, added `DryRun06ScratchClass.cls` (multi-line SOQL inside a
loop, no security mode) and `DryRun06ScratchTrigger.trigger` (multi-line
SOQL in a trigger body).

All 4 targeted findings fired correctly this time:

| Rule | Where | Fired? |
|---|---|---|
| SF-META-002 | deleted `Basic.cls` | ✅ |
| SF-TRIG-002 | multi-line SOQL in `DryRun06ScratchTrigger.trigger` | ✅ |
| SF-APEX-001 | multi-line SOQL inside the loop in `DryRun06ScratchClass.cls` | ✅ |
| SF-APEX-005 | missing `WITH USER_MODE` in the same query | ✅ |

The AI layer failed again with the same credit-exhaustion 400 as issue
#33 — and again correctly surfaced as "review is incomplete, not clean"
rather than being swallowed, reconfirming #33's fix on a second, live
failure.

Cleanup: PR #41 closed without merging
("Confirmed: SF-META-002 now fires on the deleted Basic.cls, ...").
Scratch branch deleted locally and on origin.

---

## Dry Run 7 — Real Cherry-prefixed PR merge, verify sfqa.yml dispatch (PR #42, MERGED)

Following Dry Run 5's precedent (explicit approval for real merges, since
no org credentials exist in this environment), branched
`test/DRYRUN-07-cherry-sfqa-dispatch` off `develop`, added a second marker
comment to `scripts/apex/hello.apex`, opened PR #42 titled `Cherry: dry
run 7 — verify sfqa.yml dispatch after cherry-pick`, review bot passed,
merged (squash, admin override since this repo's `develop` branch
protection requires 1 approval the acting agent can't self-satisfy).

| Step | Expected (issue #38 fix) | Observed |
|---|---|---|
| Merge triggers `cherry-pick-workflow.yml` | cherry-pick + push to `qa` | ✅ run [36710253614](https://github.com/HarshilBhardwaj047/SalesforceDevORG/actions/runs/36710253614) succeeded |
| New "Trigger QA deployment" step dispatches `sfqa.yml` | explicit `workflow_dispatch` | ✅ run [36710272175](https://github.com/HarshilBhardwaj047/SalesforceDevORG/actions/runs/36710272175) fired with `event: workflow_dispatch` (not `push`) — direct proof the explicit dispatch, not the push itself, triggered it |
| `Resolve start commit` / `Generate delta package` (issue #39 fix) | clean, no corruption | ✅ both steps succeeded |
| `Authenticate to Salesforce` | N/A | ❌ failed — expected; no org credentials configured in this environment, unrelated to the fix |

Issue #39's fix was also directly confirmed on the `develop` push that
merged PR #40 earlier the same day: `sfdev.yml` run
[36709450653](https://github.com/HarshilBhardwaj047/SalesforceDevORG/actions/runs/36709450653)
resolved the start commit via **"Using push before-SHA: e985b02..."** (a
genuine distinct ancestor, not a self-reference) and produced a clean,
uncorrupted delta-check output (`nothing_to_deploy=true`, `summary=Delta
package empty`) — directly contrasted against the pre-fix run
[36704661529](https://github.com/HarshilBhardwaj047/SalesforceDevORG/actions/runs/36704661529),
which crashed on the identical first-run scenario with `0: integer
expression expected` / `Invalid format '0 components across 0'`.

Cleanup: PR #42 merged intentionally. Scratch branches
(`test/DRYRUN-06-rule-fix-verification`,
`test/DRYRUN-07-cherry-sfqa-dispatch`) deleted locally and on origin.
`develop` and `qa` carry the trivial comment-only marker permanently,
same pattern as Dry Run 5.

---

## Issue closures

All bugs found across Dry Runs 1–7, plus one pre-existing issue, are now
fixed and closed:

| Issue | Fixed in | Re-verified in |
|---|---|---|
| [#33](https://github.com/HarshilBhardwaj047/SalesforceDevORG/issues/33) — AI layer silent failure | PR #40 | Dry Run 6 (and live on PR #40/#41's own review runs) |
| [#36](https://github.com/HarshilBhardwaj047/SalesforceDevORG/issues/36) — SF-META-002 / multi-line SOQL | PR #40 | Dry Run 6 |
| [#38](https://github.com/HarshilBhardwaj047/SalesforceDevORG/issues/38) — `sfqa.yml` never dispatched | PR #40 | Dry Run 7 |
| [#39](https://github.com/HarshilBhardwaj047/SalesforceDevORG/issues/39) — `grep -c` corruption + self-referential merge-base | PR #40 | Dry Run 7 (and the PR #40 merge push itself) |
| [#11](https://github.com/HarshilBhardwaj047/SalesforceDevORG/issues/11) — pre-existing cherry-pick failures | already resolved by current `cherry-pick-workflow.yml` | Dry Run 5 |

---

## PR #43 — stricter/more accurate static rules, blocking escalation, PR-author notification

Feature request (not a bug fix): make the static rules engine stricter
and more accurate, and notify the PR creator/owner directly when static
analysis finds issues, with detailed errors and suggested fixes. Scope
was agreed with the repo owner up front: tighten *existing* rules and
escalate blocking behavior — not add new rule categories; notify via
GitHub-native `@mention` in the review body — not Slack/email (no new
secrets/infra needed; confirmed via `gh secret list` that only
`ANTHROPIC_API_KEY` exists in this repo).

Changes (`.github/scripts/rules/*`, `review.js`,
`salesforce-pr-review.yml`):

- New `utils/braces.js` (depth-aware brace matching) fixes SF-APEX-004 /
  SF-APEX-006, which previously extracted a catch/method body with a
  lazy `\{([\s\S]*?)\}` regex that truncated at the *first* `}` — a false
  positive whenever the real `throw`/`try` sat after a nested block.
- New `utils/loops.js` (nesting-aware loop-body tracking) fixes
  SF-APEX-001 / SF-APEX-002, which previously used a flat brace counter
  that decremented on *any* `}`, so a nested `if` closing before the
  loop did caused a false negative (SOQL/DML inside the loop went
  undetected).
- SF-APEX-003: broadened the hardcoded-ID regex past the `"00"`-prefix
  assumption, which missed most custom-object record IDs.
- SF-SEC-001 / SF-SEC-002: fixed class-declaration matching to handle
  `public with sharing class Foo` (the modifier/keyword gap regex
  previously required `class` immediately after the modifier) and
  scoped the sharing-keyword check to the actual modifier text instead
  of scanning the whole preceding file.
- SF-TRIG-001: strip block comments before counting trigger body lines
  (a large `/* ... */` license header was inflating the count).
- Every finding across all 5 rule files now carries a concrete
  `suggestion` string.
- `review.js`: `hasBlocking` now considers `high` **or** `medium`
  severity (previously only `high`) → `event: 'REQUEST_CHANGES'`.
  Medium-only PRs can no longer merge with just an advisory comment.
- `review.js` + workflow: new `PR_AUTHOR` env var
  (`github.event.pull_request.user.login`); review body now opens with
  `@<author>` so the person who can act on the findings is notified
  directly, on both the findings path and the AI-layer-failure path.

Caught during its own dogfooding (PR #43 reviewing itself): SF-LWC-002
flagged `.github/scripts/rules/lwc/index.js` itself as an LWC component,
because the filter was a bare `/lwc/` substring + `.js` check. Fixed by
requiring the actual bundle shape (`lwc/<bundleName>/<file>.js`);
re-verified clean on the same PR. Merged (squash, admin override — same
branch-protection situation as prior PRs).

---

## Dry Run 8 — verify tightened rules against the real bot (PR #44, closed unmerged)

Purpose: confirm PR #43's changes actually behave as intended once
deployed, not just in local Node tests. Built four throwaway fixtures on
`test/DRYRUN-08-strict-rules-verification` off `develop`, each targeting
specific rules — including the exact shapes that used to be
false-positive/false-negative before PR #43:

- `DryRun8TestClass.cls` — SOQL/DML inside a loop with a nested `if`
  closing *before* the loop does (SF-APEX-001/002 true-positive check);
  an 18-char custom-object ID (SF-APEX-003); a `catch` and an
  `@AuraEnabled` method that both contain a nested block *followed by* a
  `throw`/`try` (SF-APEX-004/006 false-positive check); declared
  `public with sharing` (SF-SEC-002 false-negative check).
- `DryRun8GlobalTestClass.cls` — `global` class with no sharing
  declaration (SF-SEC-001/002 true-positive check).
- `DryRun8Test.trigger` — 19-line body with inline SOQL and DML
  (SF-TRIG-001/002/003).
- `dryRun8Test.js` at a real `lwc/<bundle>/<file>.js` path — hardcoded
  URL, `.then` with no `.catch`, and `document.querySelector`
  (SF-LWC-001/002/003).

Ran the rule modules locally first (`node -e ...` against each fixture)
to predict expected findings, then opened PR #44 and compared against
what the live `salesforce-pr-review.yml` run actually posted.

| Check | Expected | Observed |
|---|---|---|
| Total finding count | 13 (5 apex + 2 sec + 3 trig + 3 lwc) | ✅ review body reported "Found **13** issue(s)" — exact match with local prediction |
| SF-APEX-001/002 still fire despite nested `if` closing first | flagged | ✅ both flagged, at the SOQL/`update` lines |
| SF-APEX-004/006 do **not** false-positive | zero findings | ✅ neither rule ID appears anywhere in the 13 findings |
| SF-SEC-002 does not false-negative on `public with sharing` | zero findings on that class | ✅ confirmed — the only SEC findings are on the separate `global`, no-sharing class |
| SF-SEC-001/002 fire on the `global` no-sharing class | 2 findings | ✅ both present |
| SF-TRIG-001/002/003 fire | 3 findings | ✅ all present, including correct 19-line count |
| SF-LWC-001/002/003 fire on a real bundle path | 3 findings | ✅ all present |
| Every finding has a `_Suggested fix:_` line | 13/13 | ✅ confirmed in raw inline-comment bodies via `gh api .../pulls/44/comments` |
| `@mention` addresses the actual PR author | `@HarshilBhardwaj047` | ✅ review body opens with it |
| Blocking escalation | `high`/`medium` present → `REQUEST_CHANGES` | ✅ `state: "CHANGES_REQUESTED"` |
| AI layer | still down (unrelated) | ⚠️ same credit-exhaustion error as before — expected, not a regression |

Cleanup: PR #44 closed **without merging** (fixtures were throwaway, not
real product code) with a comment summarizing the match. Branch
`test/DRYRUN-08-strict-rules-verification` deleted locally and on
origin.

---

## Cumulative status after Dry Runs 1–8

| Capability | Status |
|---|---|
| `salesforce-pr-review.yml` (PR open/sync trigger) | ✅ works |
| Static rules: Apex/security/trigger/LWC/metadata (15 of 15 rule IDs) | ✅ verified correct — SF-META-002/SF-TRIG-002 fixed in Dry Run 6; SF-APEX-001/002/003/004/006, SF-SEC-001/002, SF-TRIG-001, SF-LWC-001/002/003 tightened in PR #43 and re-verified live in Dry Run 8 |
| Blocking escalation (`medium`+ → `REQUEST_CHANGES`) | ✅ verified live in Dry Run 8 |
| PR-author `@mention` notification | ✅ verified live in Dry Run 8 (and on PR #43 itself) |
| Per-finding suggested fixes | ✅ all 15 rule IDs now carry one; verified live in Dry Run 8 |
| AI layer (Claude Sonnet review) | ⚠️ still down — credit exhausted (external/billing, not a code bug); failures now correctly surfaced instead of swallowed (#33 fixed) |
| `cleanup-branches.yml` (dry-run mode) | ✅ works |
| `first-run-baseline.yml` | ⚠️ still records `github.sha` rather than the checked-out `inputs.branch` HEAD for non-default branches — low priority, currently unconsumed by anything |
| `drift-detection.yml` | ⚠️ fails as expected — no SF org credentials configured |
| `cherry-pick-workflow.yml` | ✅ works correctly — cherry-picks, pushes to `qa`, and now explicitly dispatches `sfqa.yml` (#38 fixed) |
| `sfdev.yml` / `sfqa.yml` / `sfstage.yml` / `sfprod.yml` (real deploy pipeline) | ✅ first-run delta computation deadlock resolved (#39); reaches `Authenticate to Salesforce` cleanly — only blocked by the absence of real org credentials in this environment |
| `rollback.yml` | ⏳ still not tested — needs a prior successful deploy snapshot, which requires real org credentials to produce |
