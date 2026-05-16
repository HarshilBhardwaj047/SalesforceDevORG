# branch-real-diff — User Guide

A practical guide to using `branch-real-diff-v3.sh` to figure out whether a diff between two branches contains *real* changes or just lines moved around.

---

## 1. Install

Drop the script anywhere on your `PATH`, or keep it in your repo's `scripts/` folder. Make it executable once:

```bash
chmod +x branch-real-diff-v3.sh
```

**Requirements:** `bash 4+`, `git`, `python3`. All three are standard on Linux/macOS; on Windows use WSL or Git Bash with Python installed.

---

## 2. 60-second quick start

From inside your git repo:

```bash
./branch-real-diff-v3.sh main feature/login
```

That's it. You get:

- A colored summary printed to your terminal
- `branch-diff-report.csv` — full per-file breakdown
- `branch-diff-report.md` — markdown summary you can paste into a PR comment

The exit code tells you the verdict: **0** = no real changes (just rearranged lines), **1** = real changes exist, **2** = something went wrong (bad args, not in a repo, etc.).

---

## 3. Understanding the output

### The terminal summary

```
 Files analyzed:           12
 Raw lines added/removed:  +247 / -198
 Real changes:             +14 / -8
 Moved (exact):            186
 Moved (fuzzy):            37

🔴 REAL differences detected.

Top 10 files by impact:
  REAL                   +12   -6    ~24   src/auth/login.py
  MOVED                  +0    -0    ~45   src/utils/helpers.py
  REARRANGED             +0    -0    ~12   src/config.py
  ...
```

The headline number is **Real changes**. If both sides are 0, the entire diff is rearrangement — no actual code behavior changed. If either side is non-zero, somebody made genuine edits.

### The verdicts

Each file gets one of these labels:

| Verdict | Meaning |
|---|---|
| `REAL` | Genuine content changes (the only one you really need to review) |
| `MOVED` | Lines moved to/from other files, no edits |
| `MOVED_IN` | New file made entirely from content relocated from elsewhere |
| `MOVED_OUT` | Deleted file whose content went to other files |
| `REARRANGED` | Lines reshuffled within the same file |
| `REFACTORED` | Lines moved *with small edits* (caught by fuzzy matching) |
| `RENAME_ONLY` | File renamed, content untouched |
| `RENAME_REFACTORED` | File renamed with light edits |
| `BINARY` | Binary file — content not analyzed, treated as opaque |
| `NOOP` | Only whitespace or sub-min-length changes |
| `IDENTICAL` | No diff at all |

For code review, you can usually skip everything except `REAL` and `RENAME_REFACTORED`.

### The CSV columns

Open `branch-diff-report.csv` in Excel/Sheets and filter by `verdict`:

| Column | What it tells you |
|---|---|
| `file` | File path |
| `status` | Git's view: modified / added / deleted / renamed |
| `lines_added` / `lines_removed` | Raw +/- from git |
| `moved_within` | Lines that left and came back inside this same file |
| `moved_cross` | Lines moved between this file and others |
| `moved_exact` | `moved_within + moved_cross` |
| `moved_fuzzy` | Lines part of a block that fuzzy-matched a block on the other side |
| `real_added` / `real_removed` | Lines with no match anywhere — the actual changes |
| `verdict` | The label from the table above |
| `notes` | Human-readable summary |

The bottom row of the CSV is a `TOTAL` summary.

---

## 4. Common scenarios

### Reviewing a pull request

```bash
./branch-real-diff-v3.sh main feature/my-pr --top 20 --verbose
```

Open `branch-diff-report.md`, scroll to "Top files by impact," and review the ones marked `REAL` first. Everything labeled `MOVED` / `REARRANGED` you can skim or trust.

### "Did this huge refactor PR actually change anything?"

```bash
./branch-real-diff-v3.sh main refactor/big-rename
```

If the headline is "🟢 No REAL content differences," the refactor is pure relocation. Merge with confidence. If it shows real changes, you know exactly which files to focus on.

### Checking your own branch before pushing

```bash
./branch-real-diff-v3.sh origin/main HEAD
```

Catches accidental edits you didn't mean to include alongside a refactor.

### Limiting to a subdirectory

```bash
./branch-real-diff-v3.sh main feature --path src/api/
```

Useful when reviewing a specific module in a giant repo.

### Comparing two specific commits

Branch names, tags, and commit SHAs all work:

```bash
./branch-real-diff-v3.sh v1.2.0 v1.3.0
./branch-real-diff-v3.sh abc1234 def5678
```

### Ignoring extra patterns

By default, lockfiles, minified bundles, and build directories are auto-filtered. Add your own:

```bash
./branch-real-diff-v3.sh main feature \
  --ignore-pattern '*.svg' \
  --ignore-pattern 'fixtures/*' \
  --ignore-pattern 'docs/generated/*'
```

To see *everything* including lockfiles:

```bash
./branch-real-diff-v3.sh main feature --include-all
```

---

## 5. Tuning the analysis

### When moves are being missed

If you have a refactor where a function moved but you also renamed a variable in it, the fuzzy matcher should catch it — but the default threshold (0.7 Jaccard similarity) might miss heavier edits. Lower it:

```bash
./branch-real-diff-v3.sh main feature --block-similarity 0.5
```

Lower = more aggressive matching (more things classified as moves). Higher = stricter (more things classified as real changes).

### When short lines cause false move-matches

In languages with a lot of `}`, `]`, `end`, `pass`, etc., these can accidentally match across files and inflate the "moved" count. The default minimum line length is 3 characters. Bump it:

```bash
./branch-real-diff-v3.sh main feature --min-line-len 8
```

### When whitespace-only changes are noise

Reformatting commits show up as massive diffs even though nothing changed:

```bash
./branch-real-diff-v3.sh main feature --ignore-whitespace
```

### Disabling fuzzy matching entirely

If you only care about exact-line moves:

```bash
./branch-real-diff-v3.sh main feature --no-fuzzy
```

Faster on huge diffs.

### Two-dot vs three-dot diff

By default, the script uses `git diff A...B` — what B has changed *since* it branched off A. This is what you want for PR review.

If you instead want the full symmetric difference (every line that differs in either direction, including changes A picked up after the branch point), use:

```bash
./branch-real-diff-v3.sh main feature --two-dot
```

---

## 6. CI integration

Because exit code 0 = no real changes and 1 = real changes, you can wire this into CI to gate or annotate PRs.

### Block merging refactor-only PRs from auto-deploying

```yaml
# .github/workflows/check-diff.yml
- name: Analyze diff
  run: |
    ./scripts/branch-real-diff-v3.sh \
      origin/main HEAD \
      --output diff-report.csv \
      --markdown diff-report.md \
      --no-color
  continue-on-error: true   # don't fail the build, just report

- name: Upload reports
  uses: actions/upload-artifact@v4
  with:
    name: diff-analysis
    path: |
      diff-report.csv
      diff-report.md
```

### Post the markdown summary as a PR comment

```yaml
- name: Comment on PR
  uses: marocchino/sticky-pull-request-comment@v2
  with:
    path: diff-report.md
```

Reviewers see the headline numbers and the top-impact files at a glance.

### Skip expensive CI steps when no real changes exist

```bash
if ./branch-real-diff-v3.sh origin/main HEAD --no-color > /dev/null; then
  echo "No real changes — skipping integration tests"
  exit 0
fi
# ... run expensive tests ...
```

---

## 7. Reading the markdown report

`branch-diff-report.md` has four sections:

1. **Headline** — the one-line verdict plus a metrics table
2. **Verdict distribution** — how many files fell into each category
3. **Top N files by impact** — sorted by real-change volume, then move volume
4. **By extension** — useful for spotting "all the real changes are in `.py`, the `.json` churn is just lockfile noise"

Drop it straight into a GitHub PR comment, a Slack message, or a code-review doc.

---

## 8. Gotchas and limitations

**The script can't tell semantic equivalence.** `x = a + b` and `x = b + a` are different lines to git, so they'll show as a real change even though the result is identical. This is fundamental to any line-based diff tool.

**Very common lines can pair up by coincidence.** `return None` in one file might "match" `return None` from a deleted function in another file. Bump `--min-line-len` if this matters, or trust that the aggregate signal is still useful even with some noise.

**Binary files are opaque.** They're flagged as `BINARY` with no further analysis. If you need to compare images or PDFs, use a dedicated tool.

**Generated code is filtered by default**, but only by filename pattern. If your generated code lives in a non-standard location, add `--ignore-pattern` flags.

**Submodule pointer changes** show up as one-line modifications and will probably be flagged `REAL`. Usually fine, occasionally surprising.

**The fuzzy matcher is greedy.** It pairs each added block with the best unmatched removed block. In rare cases with many similar blocks, the matching isn't globally optimal — but it's fast and good enough for review purposes.

---

## 9. Full options reference

```
USAGE
  branch-real-diff-v3.sh <branchA> <branchB> [options]

COMPARISON
  --two-dot              git diff A B (symmetric)
                         Default: git diff A...B (B vs merge-base, PR-style)

FILTERING
  --path <pathspec>      Limit to a path or pathspec
  --ignore-pattern <p>   Glob to exclude (repeatable, e.g. '*.svg')
  --include-all          Disable built-in noise patterns
  --ignore-whitespace    Whitespace-only changes count as no-op
  --min-line-len <N>     Min chars to consider a line (default: 3)

ANALYSIS
  --no-fuzzy             Skip block-level fuzzy move detection
  --block-similarity <F> 0-1, min similarity for fuzzy match (default: 0.7)
  --block-min-size <N>   Min block size for fuzzy match (default: 3)

OUTPUT
  --output <file>        CSV path (default: branch-diff-report.csv)
  --markdown <file>      Markdown path (default: <csv>.md; 'none' to skip)
  --top <N>              Top N files in stdout (default: 10)
  --no-color             Disable colored output

OTHER
  --verbose              Extra logs
  --help                 Show help
```

Run `./branch-real-diff-v3.sh --help` any time to refresh.

---

## 10. Cheat sheet

```bash
# Most common: review a PR branch
./branch-real-diff-v3.sh main feature/x

# Big refactor sanity check
./branch-real-diff-v3.sh main refactor/x --top 30

# Specific module only
./branch-real-diff-v3.sh main feature/x --path src/api/

# Strict (less noise)
./branch-real-diff-v3.sh main feature/x --min-line-len 8 --ignore-whitespace

# Lenient (catch more moves)
./branch-real-diff-v3.sh main feature/x --block-similarity 0.5

# CI mode (no color, plain output)
./branch-real-diff-v3.sh main HEAD --no-color --output ci.csv --markdown ci.md

# Just exit code, no files
./branch-real-diff-v3.sh main HEAD --markdown none --output /tmp/x.csv >/dev/null
echo "Exit: $?"
```
