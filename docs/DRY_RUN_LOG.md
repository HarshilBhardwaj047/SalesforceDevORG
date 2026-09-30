# Dry Run Log — Branching & Development Workflow

This log records live dry runs of the flows described in
[`docs/WORKFLOW.md`](./WORKFLOW.md) (see note below — this file does not
exist on `develop` yet, only on `master`), executed step-by-step against the
real repository to verify the documented process works as written.

---

# Dry Run 1 — Comment-only change (feature -> develop)

**Date:** 2026-09-30
**Scope:** `feature/*` branch → PR → `develop`. Stopped at the open PR (no
merge) — does not exercise `qa`/`stage`/`master` promotion or trigger any
real Salesforce deployment.

## Step 0 — Fresh pull of the repo

```bash
git fetch --all --prune
git checkout master
git pull --ff-only origin master
```

Result: fast-forwarded local `master` from `1849d36` → `fe682fd` (6 commits,
includes merge of PR #30 which added `docs/WORKFLOW.md`). Fetch also pruned
~20 stale remote branches already deleted upstream.

## Step 1 — Branch off develop

```bash
git checkout -b feature/DRYRUN-01-workflow-walkthrough origin/develop
```

Note: `develop`'s copy of `scripts/apex/hello.apex` differs slightly from
`master`'s (`SFDX:` vs `SF:` in a comment) — small pre-existing drift,
unrelated to this dry run.

## Step 2 — Develop & commit locally

Trivial, reversible change: appended a comment line to
`scripts/apex/hello.apex` (no behavior change).

```bash
git add scripts/apex/hello.apex docs/DRY_RUN_LOG.md
git commit -m "test: dry run of branching workflow (no-op comment, safe to discard)"
```

## Step 3 — Push and open PR -> develop

```bash
git push -u origin feature/DRYRUN-01-workflow-walkthrough
gh pr create --base develop --title "test: dry run of branching workflow (do not merge)" ...
```

Result: PR **[#31](https://github.com/HarshilBhardwaj047/SalesforceDevORG/pull/31)** opened.

## Step 4 — PR triggers observed

| Expected (per docs) | Observed |
|---|---|
| `Salesforce PR Review` fires on PR open | ✅ Fired within ~3s, completed in 15s, `success` |
| Static + AI review layers run | ✅ Bot posted: `✅ No issues found by static or AI layers.` (comment-only change, no logic files — cost guard #1 territory) |
| Review posted as a GitHub PR review | ✅ Authored by `github-actions[bot]`, state `COMMENTED` |
| Push a new commit -> new review fires | ✅ Second push (`synchronize` event) triggered a second review run |
| "Validation deploy against dev scratch org" on PR (WORKFLOW.md §4 step 4) | ⚠️ **Not observed** — deploys are branch-push-triggered per README.md's trigger map (`sfdev.yml` on push to `develop`), not PR-triggered. The only PR-triggered workflow is `salesforce-pr-review.yml`. Doc wording in WORKFLOW.md §4 is slightly misleading. |

## Step 5 — Stopping point (by design)

Not exercised: merge to `develop`, cherry-pick to `qa`, PR `qa`→`stage`,
`stage`→`master`, hotfix flow, branch protection enforcement.

## Cleanup performed

```bash
gh pr close 31 --comment "..."
git checkout master
git branch -D feature/DRYRUN-01-workflow-walkthrough
git push origin --delete feature/DRYRUN-01-workflow-walkthrough
```

PR #31 closed without merging. Scratch branch deleted locally and on origin.

**Bonus observation (from this cleanup):** closing PR #31 without merging
still fired `cherry-pick-workflow.yml`'s job (trigger is `pull_request:
types: [closed]`, unconditional on merge status) — but the job correctly
no-op'd (`skipped`) because its `if:` guard checks `merged == true`. Matches
WORKFLOW.md's documented trigger condition exactly.

## Summary

| WORKFLOW.md claim | Verified? |
|---|---|
| `feature/*` branches off `develop` | ✅ |
| PR to `develop` opens cleanly via `gh pr create --base develop` | ✅ |
| PR triggers `Salesforce PR Review` automatically | ✅ |
| Review bot posts a single consolidated review | ✅ |
| Comment-only Apex change -> clean pass, no findings | ✅ |
| New commit on the PR re-triggers the review | ✅ |
| "Validation deploy against dev scratch org" on PR (§4 step 4) | ⚠️ Not observed as a PR trigger — it's branch-push-triggered |

**Artifacts (closed/deleted):** branch `feature/DRYRUN-01-workflow-walkthrough`,
PR [#31](https://github.com/HarshilBhardwaj047/SalesforceDevORG/pull/31), run
[36693320631](https://github.com/HarshilBhardwaj047/SalesforceDevORG/actions/runs/36693320631).

**Post-script:** shortly after this dry run, a direct commit titled
`DRY_RUN_TEST` (`c015bd1`) landed on `master` (locally and on `origin`) —
not made as part of either dry run. It bundled this log file (as it existed
at the time) plus a pre-existing local `.vscode/settings.json` change. See
"Unrelated discovery" under Dry Run 2 below.

---

# Dry Run 2 — Real functional change (feat: getAccountsByIndustry)

**Date:** 2026-09-30
**Scope:** Same as Dry Run 1 — `feature/*` branch → PR → `develop`, stop
before merge. This time with a genuine functional change instead of a
comment-only diff, to exercise the static rules engine and the AI review
layer against real Apex logic.

## Steps executed

```bash
git fetch origin --prune
git checkout -b feature/DRYRUN-02-account-industry-filter origin/develop
```

Added `getAccountsByIndustry(String industry)` to
`force-app/main/default/classes/AccountController.cls` —
`@AuraEnabled(cacheable=true)`, `WITH USER_MODE`, blank-input guard —
following the file's existing conventions exactly. Added
`AccountControllerTest.cls` (+ meta.xml) with 3 tests (match, blank input,
no match).

```bash
git add force-app/main/default/classes/AccountController.cls \
        force-app/main/default/classes/AccountControllerTest.cls \
        force-app/main/default/classes/AccountControllerTest.cls-meta.xml
git commit -m "feat: add getAccountsByIndustry to AccountController with tests"
git push -u origin feature/DRYRUN-02-account-industry-filter
gh pr create --base develop --title "feat: add getAccountsByIndustry to AccountController" ...
```

Result: PR **[#32](https://github.com/HarshilBhardwaj047/SalesforceDevORG/pull/32)** opened.

## Observations

| Expected (per docs) | Observed |
|---|---|
| `Salesforce PR Review` fires on PR open | ✅ Completed in 12s, `pass` |
| Static rules engine runs against real logic | ✅ Log: `Static rules: 0 finding(s)` — genuinely clean (cacheable read method is exempt from the try/catch rule; `WITH USER_MODE` present) |
| AI layer engages (this is a logic-file PR, unlike Dry Run 1) | ✅ Log: `AI review: 2 logic file(s), 1 context file(s), ~1732 input tokens estimated` — cost guard #1 correctly identified this as a logic PR |
| AI layer returns findings | ❌ **API call failed**: `AI review: API call failed — 400 {"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API..."}}` |
| Bot posts final verdict | ⚠️ Posted `✅ No issues found by static or AI layers` — **indistinguishable from a real clean AI pass.** The bot's `continue-on-error` design (README.md: "review bot crash never blocks merge") means an API billing failure silently degrades to a false "all clear" rather than surfacing the error to the PR author. |

**Finding worth raising:** the `ANTHROPIC_API_KEY` account is out of
credits. The AI layer is failing on every logic-file PR right now, and the
bot gives no visible signal of this on the PR itself — only in the Action
run log. This is a real-world instance of the "AI layer is silently
skipping" troubleshooting entry in README.md, but the specific cause
(billing, not a missing key) isn't one of the two documented cases.

## Unrelated discovery: docs/ does not exist on develop

`docs/WORKFLOW.md` (and this log) only exist on `master` — they were never
merged into `develop`. `git ls-tree origin/develop` confirms no `docs/`
directory. Anyone branching a feature off `develop` (the documented,
correct way per WORKFLOW.md §4) cannot see the branching-strategy doc they're
supposed to be following. Worth merging `master`'s docs back into `develop`.

## Unrelated discovery: direct push to master succeeded

Between Dry Run 1 and Dry Run 2, commit `c015bd1` ("DRY_RUN_TEST") was
pushed **directly to `master`** — no PR. WORKFLOW.md §3/§8 states `master`
takes no direct commits and restricts pushes to admins. The push succeeded,
consistent with the repo owner having admin bypass — but it shows branch
protection is not blocking direct pushes in practice.

This triggered a `push`-to-`master` Actions run against
`.github/workflows/_reusable-deploy.yml`, which failed instantly with
"workflow file issue." Root-caused: `_reusable-deploy.yml` contains
non-ASCII em-dash bytes (`0xe2 0x80 0x94`) at two byte offsets — exactly the
failure mode documented in WORKFLOW.md §9.1 ("Workflow YAML must be
ASCII-only"). This is a **pre-existing bug**, unrelated to the DRY_RUN_TEST
commit's actual content — the same failure signature also occurred on a
`master` push back on 2026-06-17 (`_reusable-deploy.yml`, PR #13 merge). No
real deployment ran: `sfprod.yml` only triggers on push to `main`, not
`master`, so production was not touched.

## Summary

| WORKFLOW.md claim | Verified? |
|---|---|
| `feature/*` branches off `develop`, real functional change | ✅ |
| PR to `develop` opens cleanly | ✅ |
| Static rules engine analyzes real Apex logic | ✅ (0 findings, genuinely clean code) |
| AI layer engages on logic-file PRs (unlike comment-only diffs) | ✅ cost guard correctly triggers Layer 2 |
| AI layer produces a reliable verdict | ❌ API call failing (out of credits); bot masks the failure as a clean pass |
| `docs/WORKFLOW.md` accessible from `develop` | ❌ Missing — only on `master` |
| `master` direct-push protection | ⚠️ Push succeeded (admin bypass), triggered a pre-existing ASCII workflow-file bug |

**Artifacts:** branch `feature/DRYRUN-02-account-industry-filter`, PR
[#32](https://github.com/HarshilBhardwaj047/SalesforceDevORG/pull/32), run
[36700650113](https://github.com/HarshilBhardwaj047/SalesforceDevORG/actions/runs/36700650113).
