# Two-Dot vs Three-Dot Diffs — A Complete Guide

A reference for understanding `git diff A B` vs `git diff A...B`, why they differ, when to use each, and how it affects tools like `branch-real-diff-v3.sh`.

---

## 1. The mental model

Git commits form a graph. Each commit points to its parent(s). Branches are just movable labels.

When two branches share history, they look like this:

```
        D---E---F   ← branch B (tip)
       /
  A---B---C         ← branch A (tip)
```

- `B` is the commit where the two branches last shared history. This is called the **merge base**.
- After `B`, branch A added commit `C`.
- After `B`, branch B added commits `D`, `E`, and `F`.

Every diff command you'll run can be described as "compare the file tree at commit X to the file tree at commit Y." The question is always: **which X and which Y?**

---

## 2. Two-dot: `git diff A B`

### What it does

Two-dot is the direct, literal comparison. It takes the file tree at A and the file tree at B and shows every line that differs.

```
        D---E---F   ← B
       /         ↑
  A---B---C      │
            ↑    │
            └────┴── diff THESE two trees, ignoring everything else
```

It does **not** look at history. It does **not** find the merge base. It just compares two snapshots.

### Properties

- **Symmetric.** `git diff A B` and `git diff B A` show the same lines, with `+` and `-` swapped.
- **Includes all changes on both sides since the branches diverged.** Anything that A has but B doesn't will appear as a removal (because to "get to B from A" you'd have to remove it).
- **Order-independent in meaning.** Conceptually it's just "the set of lines that differ between these two trees."

### A worked example

At the merge base (commit `B`), `notes.txt` contains:

```
hello
world
```

On branch A (commit `C`), someone added a line:

```
hello
world
goodbye
```

Meanwhile on branch B (commit `F`), someone added a different line:

```
hello
world
farewell
```

`git diff A B` shows:

```diff
- goodbye
+ farewell
```

This is technically correct — to turn A's file into B's file, you'd remove `goodbye` and add `farewell`. But notice what it's telling you: it's conflating two separate developer actions ("A added `goodbye`" and "B added `farewell`") into a single artificial change. **Neither developer ever made that exact edit.**

### When two-dot is right

- Comparing two snapshots that aren't in a parent-child relationship: tagged releases, arbitrary commit SHAs, deployment environments.
- "Are these two trees actually different right now?" — environment comparison, deployment verification, config drift detection.
- When both branches received content independently (cherry-picks, parallel sync, metadata refreshes) and you want to know about the present-state difference, not who-did-what.

### When two-dot misleads

- **Reviewing a pull request.** If `main` has moved forward 20 commits since your branch forked, two-dot will show all 20 of those commits as "things your branch is removing" — pure noise.
- Any time you want to see *what one branch contributed*, rather than what's *currently different*.

---

## 3. Three-dot: `git diff A...B`

### What it does

Three-dot answers a different question: **"What has branch B done since it diverged from branch A?"**

It finds the merge base of A and B, then diffs from the merge base to B's tip.

```
        D---E---F   ← B
       /         ↑
  A---B          │
       ↑         │
       └─────────┴── diff merge-base tree to B's tree
                     (A's tip is only used to locate the merge base)
```

Internally, `git diff A...B` is equivalent to `git diff $(git merge-base A B) B`. Branch A's tip is *only* used to find the merge base — A's commits between the merge base and its tip don't appear in the output.

### Properties

- **NOT symmetric.** `git diff A...B` and `git diff B...A` are completely different outputs. `A...B` shows B's contributions; `B...A` shows A's.
- **Only B's side is shown.** Anything A added since the merge base is invisible.
- **History-aware.** Requires finding a merge base, so the branches must share ancestry.
- **What every PR review tool uses.** GitHub, GitLab, Bitbucket — they all show three-dot diffs by default for pull requests.

### A worked example

Same setup as before. Merge base `B` has:

```
hello
world
```

Branch B's tip (commit `F`) has:

```
hello
world
farewell
```

`git diff A...B` shows:

```diff
+ farewell
```

That's it. Just B's contribution. The `goodbye` line that A added doesn't appear, because A's commits aren't part of "what B did since the branches diverged."

This is much cleaner and more meaningful. It answers the question that matters during code review: *what is this branch proposing to change?*

### When three-dot is right

- **Reviewing pull requests.** This is the dominant use case.
- "What does this feature branch contribute, on top of `main`?"
- When the two branches have linear divergent history — one branched off the other and went its own way.

### When three-dot misleads

- **When both branches independently acquired the same content.** If a file was added to both branches after they diverged (parallel cherry-picks, metadata sync, multiple deployments from a shared upstream), three-dot will say B added it — and won't mention that A has it too.
- Comparing tagged releases or arbitrary snapshots that aren't in a "this branched off that" relationship.
- Comparing two long-lived deployment environment branches that get content synced into them from various sources.

---

## 4. Side-by-side comparison

| Aspect | Two-dot `A B` | Three-dot `A...B` |
|---|---|---|
| **Compares** | A's tree ↔ B's tree directly | merge-base tree → B's tree |
| **Symmetric?** | Yes — reverses sign when you flip args | No — `B...A` is a different diff entirely |
| **Includes A's commits since branching?** | Yes (shown as removals) | No |
| **Best for** | "Are these snapshots different right now?" | "What does this PR/branch contribute?" |
| **Bad when** | Reviewing a PR with a moved-on base branch | Both branches independently got the same content |
| **Used by GitHub PRs?** | No | Yes |

---

## 5. The classic "what just happened" diagram

Here's the canonical scenario where the difference bites people.

You forked `feature` off `main` two weeks ago. Since then:
- You made 3 commits on `feature`
- `main` has accepted 20 commits from other developers

```
            *---*---*   ← feature (your 3 commits)
           /
  ...-X---*---*---*---*---*---*---*---*---*---*---*---*---*---*---*---*---*---*---*---*   ← main (20 commits since X)
       ↑
       merge base
```

You open a PR for `feature → main`. What do you want to see in the diff?

**You want:** the 3 commits *you* made. The 20 unrelated commits on `main` should not appear.

**`git diff main feature` (two-dot)** shows: your 3 commits' worth of changes PLUS all 20 of `main`'s commits inverted, as if `feature` were "removing" them. Massive, confusing, mostly noise.

**`git diff main...feature` (three-dot)** shows: just your 3 commits' worth of changes. Clean.

This is why every PR review tool defaults to three-dot, and why `branch-real-diff-v3.sh` does too.

---

## 6. The trap: independent identical additions

This is the case that bit you with the Salesforce permission set file. Picture:

```
            D---E---F   ← branch B (added Sales_Strategy.xml at commit E)
           /
  ...-X---*---C---G     ← branch A (added Sales_Strategy.xml at commit G, independently)
       ↑
       merge base
```

At the merge base, `Sales_Strategy.xml` doesn't exist. On both A's and B's tips, it exists. Maybe identical content, maybe slightly different — both branches received it through separate paths (sandbox refresh, cherry-pick, manual upload, whatever).

**Two-dot `git diff A B`:**
- A has the file. B has the file.
- If identical: no diff at all.
- If slightly different: only the differing lines.
- **Verdict you'd want: "they're the same" or "they differ in these few lines."**

**Three-dot `git diff A...B`:**
- Merge base doesn't have the file. B has it.
- Result: "B added this file with 3693 lines."
- A's existing copy is invisible — A's history isn't consulted.
- **Verdict: misleading. The file isn't new; it's already on both branches.**

This is exactly what `branch-real-diff-v3.sh` was reporting. Not a bug — three-dot is doing exactly what three-dot is supposed to do — but the wrong tool for that situation.

---

## 7. How `branch-real-diff-v3.sh` handles this

The script defaults to three-dot because most use cases are PR-style review. But it provides `--two-dot` for cases like yours.

### Default (three-dot) behavior

```bash
./branch-real-diff-v3.sh main feature
```

Internally runs `git diff merge-base(main, feature) feature`. Shows what feature contributed since the branches diverged. Ideal for code review.

### Two-dot behavior

```bash
./branch-real-diff-v3.sh main feature --two-dot
```

Internally runs `git diff main feature`. Shows everything that's literally different between the two tips, regardless of history. Ideal for environment comparison, Salesforce metadata work, and any case where both branches got content through parallel paths.

---

## 8. A practical decision rule

Use **three-dot** (default) when:

- Reviewing a pull request
- Asking "what did this feature branch contribute?"
- The branches have a clean divergent history — one branched off the other and went its own way
- You want to ignore changes that landed on the base branch after the fork point

Use **two-dot** (`--two-dot`) when:

- Both branches received content independently (cherry-picks, parallel sync, metadata refreshes)
- Salesforce work, where branches often represent orgs/environments rather than feature work
- Comparing tagged releases, deployment snapshots, or arbitrary commit SHAs
- You want to answer "are these two trees actually different right now?"
- Infrastructure-as-code or config repos where branches map to environments

When in doubt: run both. Two-dot gives you ground truth ("these are the actual byte-level differences"); three-dot gives you the contribution-of-this-branch view. If they differ wildly, one branch has been independently picking up changes — and that's useful information by itself.

---

## 9. Verifying which case you're in

When something looks wrong in a diff (like a file showing as "newly added" when you know it exists on both branches), run this triage:

```bash
# 1. Find the merge base
git merge-base <branchA> <branchB>
```

```bash
# 2. Check if the file exists at the merge base
git cat-file -e $(git merge-base <branchA> <branchB>):path/to/file \
  && echo "exists at merge-base" \
  || echo "NOT at merge-base"
```

```bash
# 3. Check each branch tip
git cat-file -e <branchA>:path/to/file && echo "exists on A" || echo "missing on A"
git cat-file -e <branchB>:path/to/file && echo "exists on B" || echo "missing on B"
```

If you see "NOT at merge-base" but "exists on A" and "exists on B" — confirmed. The file was added independently to both branches. Switch to `--two-dot`.

```bash
# 4. Compare what two-dot vs three-dot say
git diff --stat <branchA> <branchB> -- path/to/file       # two-dot
git diff --stat <branchA>...<branchB> -- path/to/file     # three-dot
```

The line counts will probably differ dramatically.

---

## 10. Salesforce-specific guidance

Salesforce metadata work routinely violates the assumptions three-dot is built on. Here's why:

- **Branches often map to orgs**, not features. Sandbox-A and Sandbox-B are environments, not "Sandbox-B is what Sandbox-A would be if I added some commits."
- **Content arrives via deployment**, not authoring. Change sets, packages, and refreshes drop files into branches independently of git history.
- **Sandbox refreshes** can bring large batches of metadata into a branch that already exists elsewhere.

For most Salesforce diff work, **use `--two-dot`** as your default. The PR-review semantics of three-dot rarely apply.

If you want to make `--two-dot` your team standard, alias it:

```bash
# in ~/.bashrc or ~/.zshrc
alias sfdiff='./branch-real-diff-v3.sh --two-dot'
```

Then `sfdiff main feature` does what you want.

---

## 11. The four-dot myth

You might wonder if there's a four-dot syntax. There isn't — `..` and `...` are the only two. Some people misremember "three-dot" as the "every line in either A or B" version because of set-theory symmetry with how `..` works in `git log`, but for `git diff` specifically:

- `git diff A..B` is treated the same as `git diff A B` (two-dot)
- `git diff A...B` is three-dot (merge-base to B)

(Note: in `git log`, the meanings are different again — `A..B` means "commits reachable from B but not A," and `A...B` means "commits reachable from either but not both." Don't conflate `git diff` semantics with `git log` semantics.)

---

## 12. Cheat sheet

```bash
# Reviewing a PR — three-dot (script default)
./branch-real-diff-v3.sh main feature/login

# Comparing environments / Salesforce orgs — two-dot
./branch-real-diff-v3.sh sandbox-uat sandbox-prod --two-dot

# Comparing release tags — two-dot
./branch-real-diff-v3.sh v1.2.0 v1.3.0 --two-dot

# Checking your own branch before pushing — three-dot (default)
./branch-real-diff-v3.sh origin/main HEAD

# Suspicious "newly added file" — verify with both
./branch-real-diff-v3.sh main feature           # three-dot view
./branch-real-diff-v3.sh main feature --two-dot # two-dot view (ground truth)
```

```bash
# Manual git equivalents (no script)
git diff main feature              # two-dot
git diff main...feature            # three-dot
git diff $(git merge-base main feature) feature   # explicit three-dot
```

---

## 13. Summary in one paragraph

`git diff A B` (two-dot) compares two snapshots directly and shows everything that differs, symmetric, no history awareness. `git diff A...B` (three-dot) finds the merge base of A and B, then shows only what B added since then — perfect for PR review, useless when both branches received content independently. The `branch-real-diff-v3.sh` script defaults to three-dot for PR review, but accepts `--two-dot` for cases like Salesforce metadata work where branches represent environments rather than features and content arrives via deployment rather than commit. When a file looks "newly added" but you know it exists on both branches, three-dot is misleading you — switch to two-dot.
