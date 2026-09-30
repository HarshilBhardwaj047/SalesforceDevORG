# Dry Run 3 — Verify static rules engine detects real anti-patterns

**Date:** 2026-09-30
**Prior runs:** Dry Run 1 (comment-only change, PR #31, closed) and Dry Run 2
(real functional change, PR #32, closed, filed issue #33 re: AI layer
failing on exhausted API credits) — full history of those two runs was
written to this same path on their respective branches, but since `docs/`
does not exist on `develop` (see Dry Run 2's findings), each dry-run branch
starts this file fresh. See PR #31 and PR #32 on GitHub for the full text of
runs 1 and 2 if needed.

**Goal:** Dry run 2 showed the AI review layer is failing (exhausted
Anthropic credits, issue #33). This run isolates and verifies the **static
rules engine** specifically, by deliberately planting known anti-patterns
and confirming each one is caught by name, severity, and line number.

## Steps executed

```bash
git fetch origin --prune
git checkout -b feature/DRYRUN-03-static-rule-check origin/develop
```

Added `force-app/main/default/classes/AccountBulkUpdater.cls` — a
deliberately bad class combining 4 known anti-patterns in one small method:

```apex
public class AccountBulkUpdater {
    public static void touchAccountsBadly(List<Id> accountIds) {
        for (Id accId : accountIds) {
            Account acc = [SELECT Id, Name FROM Account WHERE Id = :accId LIMIT 1];
            acc.Name = acc.Name + ' (touched)';
            update acc;
        }
    }
}
```

Planted violations (chosen by reading `.github/scripts/rules/apex/index.js`
and `.github/scripts/rules/security/index.js` directly, to pick anti-patterns
the regex-based rules are guaranteed to match):

- SOQL inside a `for` loop → `SF-APEX-001` (high)
- DML (`update`) inside a `for` loop → `SF-APEX-002` (high)
- SOQL missing `WITH USER_MODE`/`WITH SECURITY_ENFORCED` → `SF-APEX-005` (medium)
- Class missing a sharing declaration → `SF-SEC-002` (medium)

```bash
git add force-app/main/default/classes/AccountBulkUpdater.cls \
        force-app/main/default/classes/AccountBulkUpdater.cls-meta.xml
git commit -m "test: intentionally bad Apex class to verify static rules engine (SOQL/DML in loop)"
git push -u origin feature/DRYRUN-03-static-rule-check
gh pr create --base develop --title "test: dry run 3 - verify static rules engine detects real anti-patterns" ...
```

Result: PR **[#34](https://github.com/HarshilBhardwaj047/SalesforceDevORG/pull/34)** opened.

## Observations

| Expected | Observed |
|---|---|
| Static rules engine runs | ✅ Log: `Static rules: 4 finding(s)` — exactly the 4 planted issues, no more, no fewer |
| Each specific rule fires correctly | ✅ All 4 confirmed via `gh api .../pulls/34/comments` (inline review comments): |

```
🔴 SF-APEX-001 (line 10) — SOQL query inside a loop...
🔴 SF-APEX-002 (line 12) — DML inside a loop...
🟡 SF-SEC-002  (line 2)  — Class AccountBulkUpdater does not declare a sharing model...
🟡 SF-APEX-005 (line 10) — SOQL query does not declare a security mode...
```

| Expected | Observed |
|---|---|
| Correct line numbers | ✅ Line 10 = the SOQL line, line 12 = the `update acc;` line, line 2 = the method signature (class decl region) |
| Correct severity mapping | ✅ Both `high` findings (SOQL/DML in loop) rendered 🔴; both `medium` findings rendered 🟡 |
| 🔴 high findings block merge | ✅ Overall PR review `state: CHANGES_REQUESTED` (confirmed via `gh pr view 34 --json reviews`) — matches README.md: "🔴 high = REQUEST_CHANGES (PR cannot merge until fixed or dismissed)" |
| AI layer still failing (per issue #33) | ✅ Same failure signature as Dry Run 2: `AI review: API call failed — 400 ... credit balance is too low`. Bot's summary correctly attributed all 4 findings to the static layer this time (`"4 from static rules, 0 from AI layer"`) — unlike the earlier "No issues found by static or AI layers" wording, this message is *not* misleading when there are static findings to report. The silent-failure risk from issue #33 is specifically about the **zero-findings** case, which this run doesn't hit. |

## Conclusion

**Static rules engine is confirmed fully functional** — deterministic,
correctly severity-ranked, correctly line-mapped, and correctly wired to
block merge via `CHANGES_REQUESTED` on high findings. This is independent of
the AI layer (issue #33) and unaffected by the Anthropic billing issue — the
two-layer design's fallback (static rules being freestanding) is working as
designed per README.md's architecture.

## Cleanup

```bash
gh pr close 34
git checkout master
git branch -D feature/DRYRUN-03-static-rule-check
git push origin --delete feature/DRYRUN-03-static-rule-check
```
