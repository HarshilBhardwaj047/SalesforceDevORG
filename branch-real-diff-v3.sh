#!/usr/bin/env bash
#
# branch-real-diff-v3.sh
# ----------------------
# Classify a diff between two branches as REAL changes vs MOVED lines.
# Outputs a CSV report and a Markdown summary.
#
# Requires: bash 4+, git, python3
#
# See --help for full options.

set -euo pipefail
VERSION="3.0"

# ====================== HELP ======================
show_help() {
  cat <<'EOF'
branch-real-diff v3 — classify diffs as real changes vs moved lines

USAGE
  branch-real-diff-v3.sh <branchA> <branchB> [options]

COMPARISON
  --two-dot              git diff A B (symmetric)
                         Default: git diff A...B (B vs merge-base, PR-style)

FILTERING
  --path <pathspec>      Limit to a path or pathspec
  --ignore-pattern <p>   Glob to exclude (repeatable, e.g. '*.svg')
  --include-all          Disable built-in noise patterns (lockfiles, dist/, etc.)
  --ignore-whitespace    Whitespace-only changes count as no-op
  --min-line-len <N>     Min chars to consider a line for move matching (default: 3)

ANALYSIS
  --no-fuzzy             Skip block-level fuzzy move detection
  --block-similarity <F> 0-1, min similarity for fuzzy block match (default: 0.7)
  --block-min-size <N>   Min block size to consider fuzzy match (default: 3)

OUTPUT
  --output <file>        CSV path (default: branch-diff-report.csv)
  --markdown <file>      Markdown summary path (default: <csv>.md; 'none' to skip)
  --top <N>              Top N files to show in stdout (default: 10)
  --no-color             Disable colored output

OTHER
  --verbose              Extra logs
  --help                 This help

EXIT CODES
  0 = no real differences   1 = real differences   2 = usage / setup error

EXAMPLES
  branch-real-diff-v3.sh main feature/login
  branch-real-diff-v3.sh main HEAD --path src/ --ignore-pattern '*.snap'
  branch-real-diff-v3.sh origin/main HEAD --output pr.csv --top 20 --verbose
EOF
}

# ====================== ARGS ======================
[[ $# -lt 1 ]] && { show_help; exit 2; }
[[ "$1" == "--help" || "$1" == "-h" ]] && { show_help; exit 0; }
[[ $# -lt 2 ]] && { echo "ERROR: need <branchA> <branchB>" >&2; exit 2; }

BRANCH_A="$1"; BRANCH_B="$2"; shift 2

TWO_DOT=0
SUBPATH=""
OUTPUT="branch-diff-report.csv"
MARKDOWN=""
IGNORE_WS=0
MIN_LEN=3
NO_FUZZY=0
BLOCK_SIM=0.7
BLOCK_MIN=3
TOP_N=10
NO_COLOR=0
VERBOSE=0
INCLUDE_ALL=0
declare -a USER_IGNORES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --two-dot)            TWO_DOT=1; shift ;;
    --path)               SUBPATH="$2"; shift 2 ;;
    --ignore-pattern)     USER_IGNORES+=("$2"); shift 2 ;;
    --include-all)        INCLUDE_ALL=1; shift ;;
    --ignore-whitespace)  IGNORE_WS=1; shift ;;
    --min-line-len)       MIN_LEN="$2"; shift 2 ;;
    --no-fuzzy)           NO_FUZZY=1; shift ;;
    --block-similarity)   BLOCK_SIM="$2"; shift 2 ;;
    --block-min-size)     BLOCK_MIN="$2"; shift 2 ;;
    --output)             OUTPUT="$2"; shift 2 ;;
    --markdown)           MARKDOWN="$2"; shift 2 ;;
    --top)                TOP_N="$2"; shift 2 ;;
    --no-color)           NO_COLOR=1; shift ;;
    --verbose)            VERBOSE=1; shift ;;
    --help|-h)            show_help; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -z "$MARKDOWN" ]] && MARKDOWN="${OUTPUT%.csv}.md"

# Colors
if [[ $NO_COLOR -eq 1 || ! -t 1 ]]; then
  C_RED=""; C_GRN=""; C_YEL=""; C_BOLD=""; C_DIM=""; C_NC=""
else
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_NC=$'\033[0m'
fi

log()  { [[ $VERBOSE -eq 1 ]] && echo "${C_DIM}[info]${C_NC} $*" >&2 || true; }
warn() { echo "${C_YEL}[warn]${C_NC} $*" >&2; }
err()  { echo "${C_RED}[err]${C_NC}  $*" >&2; }

# ====================== VALIDATION ======================
command -v python3 >/dev/null 2>&1 || { err "python3 required but not found"; exit 2; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { err "not inside a git repo"; exit 2; }

for B in "$BRANCH_A" "$BRANCH_B"; do
  git rev-parse --verify "$B" >/dev/null 2>&1 || { err "ref not found: $B"; exit 2; }
done

# ====================== DIFF RANGE ======================
if [[ $TWO_DOT -eq 1 ]]; then
  DIFF_FROM="$BRANCH_A"; DIFF_TO="$BRANCH_B"
  RANGE_DESC="$BRANCH_A ↔ $BRANCH_B (two-dot)"
else
  MERGE_BASE="$(git merge-base "$BRANCH_A" "$BRANCH_B" 2>/dev/null || true)"
  if [[ -z "$MERGE_BASE" ]]; then
    warn "no common ancestor; falling back to two-dot"
    DIFF_FROM="$BRANCH_A"; DIFF_TO="$BRANCH_B"
    RANGE_DESC="$BRANCH_A ↔ $BRANCH_B (no merge-base, two-dot)"
  else
    DIFF_FROM="$MERGE_BASE"; DIFF_TO="$BRANCH_B"
    RANGE_DESC="$BRANCH_B vs merge-base($BRANCH_A,$BRANCH_B)=${MERGE_BASE:0:8}"
  fi
fi

WS_FLAG=""
[[ $IGNORE_WS -eq 1 ]] && WS_FLAG="-w"

declare -a PATH_ARGS=()
[[ -n "$SUBPATH" ]] && PATH_ARGS=(-- "$SUBPATH")

# ====================== IGNORE PATTERNS ======================
declare -a IGNORE_PATTERNS=()
if [[ $INCLUDE_ALL -eq 0 ]]; then
  IGNORE_PATTERNS+=(
    'package-lock.json' 'yarn.lock' 'pnpm-lock.yaml' 'npm-shrinkwrap.json'
    'Cargo.lock' 'go.sum' 'Gemfile.lock' 'poetry.lock' 'composer.lock'
    'Pipfile.lock' 'mix.lock' '*.lockb'
    '*.min.js' '*.min.css' '*.map'
    'dist/*' 'build/*' 'node_modules/*' 'vendor/*' '.next/*' 'target/*'
    '*.snap' '__snapshots__/*'
  )
fi
IGNORE_PATTERNS+=("${USER_IGNORES[@]}")

# ====================== TEMP ======================
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

BOOTSTRAP="$TMPDIR/bootstrap.json"
RESULT="$TMPDIR/result.json"
NUMSTAT="$TMPDIR/numstat.txt"
NAMESTAT="$TMPDIR/namestatus.txt"
IGNORE_FILE="$TMPDIR/ignore.txt"

# ====================== EARLY EXIT IF NO DIFF ======================
if git diff --quiet $WS_FLAG "$DIFF_FROM" "$DIFF_TO" "${PATH_ARGS[@]}"; then
  echo "${C_GRN}✅ Branches are identical — no diff at all.${C_NC}"
  echo "file,status,lines_added,lines_removed,moved_within,moved_cross,moved_exact,moved_fuzzy,real_added,real_removed,verdict,notes" > "$OUTPUT"
  echo "All files,unchanged,0,0,0,0,0,0,0,0,IDENTICAL,no differences" >> "$OUTPUT"
  [[ "$MARKDOWN" != "none" ]] && printf '# Branch Diff Report\n\n**No differences.**\n' > "$MARKDOWN"
  exit 0
fi

# ====================== GATHER FILE LIST ======================
log "Collecting file list..."

if [[ -n "$WS_FLAG" ]]; then
  git diff --numstat     --find-renames "$WS_FLAG" "$DIFF_FROM" "$DIFF_TO" "${PATH_ARGS[@]}" > "$NUMSTAT"
  git diff --name-status --find-renames "$WS_FLAG" "$DIFF_FROM" "$DIFF_TO" "${PATH_ARGS[@]}" > "$NAMESTAT"
else
  git diff --numstat     --find-renames "$DIFF_FROM" "$DIFF_TO" "${PATH_ARGS[@]}" > "$NUMSTAT"
  git diff --name-status --find-renames "$DIFF_FROM" "$DIFF_TO" "${PATH_ARGS[@]}" > "$NAMESTAT"
fi

# Write ignore patterns to a file (newline-delimited, easy for python to read)
: > "$IGNORE_FILE"
for p in "${IGNORE_PATTERNS[@]:-}"; do
  [[ -n "$p" ]] && printf '%s\n' "$p" >> "$IGNORE_FILE"
done

# ====================== BUILD BOOTSTRAP JSON ======================
log "Building bootstrap..."

# Pass paths as arguments (avoids env-var quoting traps)
python3 - "$NUMSTAT" "$NAMESTAT" "$IGNORE_FILE" \
  "$MIN_LEN" "$IGNORE_WS" "$NO_FUZZY" "$BLOCK_SIM" "$BLOCK_MIN" \
  "$DIFF_FROM" "$DIFF_TO" "$WS_FLAG" > "$BOOTSTRAP" <<'PYBOOT'
import json, sys, os, fnmatch, re

(numstat_p, namestat_p, ignore_p,
 min_len, ignore_ws, no_fuzzy, block_sim, block_min,
 diff_from, diff_to, ws_flag) = sys.argv[1:12]

ns_lines  = open(numstat_p).read().splitlines()
nst_lines = open(namestat_p).read().splitlines()
ignore_pats = [l for l in open(ignore_p).read().splitlines() if l]

def matches_ignore(path):
    base = os.path.basename(path)
    for pat in ignore_pats:
        if fnmatch.fnmatch(path, pat) or fnmatch.fnmatch(base, pat):
            return True
        # 'dir/*' means anywhere under dir/
        if pat.endswith("/*"):
            prefix = pat[:-2]
            if path.startswith(prefix + "/") or ("/" + prefix + "/") in ("/" + path):
                return True
    return False

# Map status letters from --name-status
status_map = {}
rename_from = {}
for line in nst_lines:
    parts = line.split("\t")
    if len(parts) < 2: continue
    st = parts[0]
    if (st.startswith("R") or st.startswith("C")) and len(parts) >= 3:
        status_map[parts[2]] = "renamed"
        rename_from[parts[2]] = parts[1]
    elif st == "A": status_map[parts[1]] = "added"
    elif st == "D": status_map[parts[1]] = "deleted"
    elif st == "M": status_map[parts[1]] = "modified"
    elif st == "T": status_map[parts[1]] = "type-changed"
    else: status_map[parts[1]] = st

files, ignored = [], []
for line in ns_lines:
    parts = line.split("\t")
    if len(parts) < 3: continue
    added, removed, path_field = parts[0], parts[1], parts[2]
    if "=>" in path_field:
        m = re.match(r"^(.*)\{(.*) => (.*)\}(.*)$", path_field)
        if m:
            path = m.group(1) + m.group(3) + m.group(4)
        else:
            m2 = re.match(r"^(.*) => (.*)$", path_field)
            path = m2.group(2) if m2 else path_field
        path = path.replace("//", "/")
    else:
        path = path_field

    if matches_ignore(path):
        ignored.append(path); continue

    is_binary = (added == "-")
    files.append({
        "path": path,
        "status": status_map.get(path, "modified"),
        "rename_from": rename_from.get(path),
        "binary": is_binary,
        "lines_added": 0 if is_binary else int(added),
        "lines_removed": 0 if is_binary else int(removed),
    })

bootstrap = {
    "config": {
        "min_line_len": int(min_len),
        "ignore_ws": ignore_ws == "1",
        "fuzzy": no_fuzzy == "0",
        "block_similarity": float(block_sim),
        "block_min_size": int(block_min),
    },
    "diff": {"from": diff_from, "to": diff_to, "ws_flag": ws_flag},
    "files": files,
    "ignored": ignored,
}
json.dump(bootstrap, sys.stdout)
PYBOOT

NUM_FILES=$(python3 -c "import json; print(len(json.load(open('$BOOTSTRAP'))['files']))")
NUM_IGNORED=$(python3 -c "import json; print(len(json.load(open('$BOOTSTRAP'))['ignored']))")
log "Analyzing $NUM_FILES files (filtered out $NUM_IGNORED noise files)"

if [[ "$NUM_FILES" -eq 0 ]]; then
  echo "${C_YEL}🟡 All changed files were filtered out by ignore patterns.${C_NC}"
  echo "file,status,lines_added,lines_removed,moved_within,moved_cross,moved_exact,moved_fuzzy,real_added,real_removed,verdict,notes" > "$OUTPUT"
  exit 0
fi

# ====================== ANALYSIS ======================
log "Running analysis..."

python3 - "$BOOTSTRAP" "$RESULT" <<'PYANALYZE'
import json, sys, subprocess, re
from collections import Counter

with open(sys.argv[1]) as fh:
    boot = json.load(fh)

cfg  = boot["config"]
diff = boot["diff"]
files = boot["files"]

MIN_LEN    = cfg["min_line_len"]
IGNORE_WS  = cfg["ignore_ws"]
FUZZY      = cfg["fuzzy"]
BLOCK_SIM  = cfg["block_similarity"]
BLOCK_MIN  = cfg["block_min_size"]

_ws_re = re.compile(r"\s+")
def normalize(s):
    return _ws_re.sub(" ", s).strip() if IGNORE_WS else s

def significant(s):
    return len(normalize(s).strip()) >= MIN_LEN

# Pull hunks for every non-binary file
def get_hunks(path, status, rfrom):
    args = ["git", "diff", "-U0", "--no-color"]
    if diff["ws_flag"]: args.append(diff["ws_flag"])
    args += [diff["from"], diff["to"], "--"]
    if status == "renamed" and rfrom:
        args.extend([rfrom, path])
    else:
        args.append(path)
    try:
        out = subprocess.check_output(args, stderr=subprocess.DEVNULL).decode("utf-8", "replace")
    except subprocess.CalledProcessError:
        return []
    hunks, cur = [], None
    for line in out.split("\n"):
        if line.startswith("@@"):
            if cur is not None: hunks.append(cur)
            cur = {"added": [], "removed": []}
        elif cur is None or line.startswith("+++") or line.startswith("---"):
            continue
        elif line.startswith("+"):
            cur["added"].append(line[1:])
        elif line.startswith("-"):
            cur["removed"].append(line[1:])
    if cur is not None: hunks.append(cur)
    return hunks

for f in files:
    f["hunks"] = [] if f["binary"] else get_hunks(f["path"], f["status"], f.get("rename_from"))

# Per-file multisets of normalized significant lines
file_added, file_removed = [], []
for f in files:
    a, r = Counter(), Counter()
    for h in f["hunks"]:
        for line in h["added"]:
            if significant(line): a[normalize(line)] += 1
        for line in h["removed"]:
            if significant(line): r[normalize(line)] += 1
    file_added.append(a); file_removed.append(r)

# Within-file exact moves
within = []
for i in range(len(files)):
    w = Counter(); a, r = file_added[i], file_removed[i]
    for line in a:
        m = min(a[line], r[line])
        if m: w[line] = m
    within.append(w)

# Cross-file exact moves: pool what's left after within
rem_added, rem_removed = Counter(), Counter()
for i in range(len(files)):
    rem_added   += file_added[i]   - within[i]
    rem_removed += file_removed[i] - within[i]
cross_pool = Counter({l: min(rem_added[l], rem_removed[l]) for l in rem_added})

cross_in  = [Counter() for _ in files]
cross_out = [Counter() for _ in files]
left = Counter(cross_pool)
for i in range(len(files)):
    a_rem = file_added[i] - within[i]
    for line in a_rem:
        take = min(a_rem[line], left[line])
        if take: cross_in[i][line] = take; left[line] -= take
left = Counter(cross_pool)
for i in range(len(files)):
    r_rem = file_removed[i] - within[i]
    for line in r_rem:
        take = min(r_rem[line], left[line])
        if take: cross_out[i][line] = take; left[line] -= take

real_a = [file_added[i]   - within[i] - cross_in[i]  for i in range(len(files))]
real_r = [file_removed[i] - within[i] - cross_out[i] for i in range(len(files))]

# Fuzzy block matching on the leftover real lines
fuzzy_a = [Counter() for _ in files]
fuzzy_r = [Counter() for _ in files]
if FUZZY:
    added_blocks, removed_blocks = [], []
    for i, f in enumerate(files):
        if f["binary"]: continue
        ra, rr = Counter(real_a[i]), Counter(real_r[i])
        for h in f["hunks"]:
            blk = []
            for line in h["added"]:
                if not significant(line): continue
                nl = normalize(line)
                if ra[nl] > 0:
                    blk.append(nl); ra[nl] -= 1
            if len(blk) >= BLOCK_MIN:
                added_blocks.append((i, blk))
            blk = []
            for line in h["removed"]:
                if not significant(line): continue
                nl = normalize(line)
                if rr[nl] > 0:
                    blk.append(nl); rr[nl] -= 1
            if len(blk) >= BLOCK_MIN:
                removed_blocks.append((i, blk))

    def jaccard(a, b):
        ca, cb = Counter(a), Counter(b)
        inter = sum((ca & cb).values())
        union = sum((ca | cb).values())
        return inter / union if union else 0.0

    used = set()
    for ai, a_lines in added_blocks:
        best_sim, best = 0.0, -1
        for idx, (ri, r_lines) in enumerate(removed_blocks):
            if idx in used: continue
            if abs(len(a_lines) - len(r_lines)) > max(len(a_lines), len(r_lines)):
                continue
            sim = jaccard(a_lines, r_lines)
            if sim > best_sim:
                best_sim, best = sim, idx
        if best >= 0 and best_sim >= BLOCK_SIM:
            used.add(best)
            ri, r_lines = removed_blocks[best]
            for line in a_lines:
                if real_a[ai][line] > 0:
                    real_a[ai][line] -= 1
                    fuzzy_a[ai][line] += 1
            for line in r_lines:
                if real_r[ri][line] > 0:
                    real_r[ri][line] -= 1
                    fuzzy_r[ri][line] += 1

def vc(c): return sum(c.values())

results = []
for i, f in enumerate(files):
    mw = vc(within[i])
    mc = vc(cross_in[i]) + vc(cross_out[i])
    me = mw + mc
    mf = vc(fuzzy_a[i]) + vc(fuzzy_r[i])
    ra = vc(real_a[i])
    rr = vc(real_r[i])
    st = f["status"]

    if f["binary"]:
        verdict, notes = "BINARY", "binary file, content not analyzed"
    elif st == "added":
        verdict, notes = ("MOVED_IN","content came from other file(s)") if (ra==0 and mc>0) else ("REAL","new file")
    elif st == "deleted":
        verdict, notes = ("MOVED_OUT","content went to other file(s)") if (rr==0 and mc>0) else ("REAL","file removed")
    elif st == "renamed":
        if ra==0 and rr==0 and mf==0: verdict, notes = "RENAME_ONLY", "pure rename"
        elif ra==0 and rr==0:         verdict, notes = "RENAME_REFACTORED", "renamed with light edits"
        else:                         verdict, notes = "REAL", "renamed with content changes"
    else:
        if ra==0 and rr==0:
            if mf > 0 and me == 0:    verdict, notes = "REFACTORED", "lines moved with edits"
            elif mw > 0 and mc == 0:  verdict, notes = "REARRANGED", "lines reshuffled within file"
            elif mc > 0:              verdict, notes = "MOVED", "lines moved to/from other files"
            else:                     verdict, notes = "NOOP", "whitespace or sub-min-length only"
        else:
            verdict = "REAL"
            notes = "real edits + some movement" if (me + mf) > 0 else "genuine edits"

    results.append({
        "file": f["path"], "status": st, "binary": f["binary"],
        "lines_added": f["lines_added"], "lines_removed": f["lines_removed"],
        "moved_within": mw, "moved_cross": mc, "moved_exact": me, "moved_fuzzy": mf,
        "real_added": ra, "real_removed": rr,
        "verdict": verdict, "notes": notes,
    })

totals = {
    "files": len(results),
    "lines_added":   sum(r["lines_added"]   for r in results),
    "lines_removed": sum(r["lines_removed"] for r in results),
    "moved_exact":   sum(r["moved_exact"]   for r in results),
    "moved_fuzzy":   sum(r["moved_fuzzy"]   for r in results),
    "real_added":    sum(r["real_added"]    for r in results),
    "real_removed":  sum(r["real_removed"]  for r in results),
}

ext_stats = {}
for r in results:
    base = r["file"].rsplit("/", 1)[-1]
    ext = base.rsplit(".", 1)[-1] if "." in base else "(none)"
    s = ext_stats.setdefault(ext, {"files":0,"real_added":0,"real_removed":0,"moved_exact":0,"moved_fuzzy":0})
    s["files"] += 1
    for k in ("real_added","real_removed","moved_exact","moved_fuzzy"):
        s[k] += r[k]

with open(sys.argv[2], "w") as out:
    json.dump({"results": results, "totals": totals, "ext_stats": ext_stats}, out)
PYANALYZE

# ====================== WRITE CSV ======================
log "Writing CSV..."
python3 - "$RESULT" "$OUTPUT" <<'PYCSV'
import json, csv, sys
data = json.load(open(sys.argv[1]))
with open(sys.argv[2], "w", newline="") as out:
    w = csv.writer(out)
    w.writerow(["file","status","lines_added","lines_removed",
                "moved_within","moved_cross","moved_exact","moved_fuzzy",
                "real_added","real_removed","verdict","notes"])
    for r in data["results"]:
        w.writerow([r["file"], r["status"], r["lines_added"], r["lines_removed"],
                    r["moved_within"], r["moved_cross"], r["moved_exact"], r["moved_fuzzy"],
                    r["real_added"], r["real_removed"], r["verdict"], r["notes"]])
    t = data["totals"]
    ov = "NO_REAL_DIFF" if (t["real_added"]==0 and t["real_removed"]==0) else "REAL_DIFF"
    w.writerow(["TOTAL","summary",t["lines_added"],t["lines_removed"],
                "","",t["moved_exact"],t["moved_fuzzy"],
                t["real_added"],t["real_removed"],ov,f"{t['files']} files analyzed"])
PYCSV

# ====================== WRITE MARKDOWN ======================
if [[ "$MARKDOWN" != "none" ]]; then
  log "Writing Markdown..."
  python3 - "$RESULT" "$MARKDOWN" "$RANGE_DESC" "$TOP_N" <<'PYMD'
import json, sys
data = json.load(open(sys.argv[1]))
out_path, range_desc, top_n = sys.argv[2], sys.argv[3], int(sys.argv[4])
results, totals, ext = data["results"], data["totals"], data["ext_stats"]

sorted_r = sorted(results, key=lambda r: (-(r["real_added"]+r["real_removed"]),
                                          -(r["moved_exact"]+r["moved_fuzzy"])))
vc = {}
for r in results: vc[r["verdict"]] = vc.get(r["verdict"], 0) + 1
headline = ("🟢 No real differences — diff is pure rearrangement"
            if (totals["real_added"]==0 and totals["real_removed"]==0)
            else "🔴 Real differences detected")

L = []
L.append("# Branch Diff Report\n")
L.append(f"**Range:** `{range_desc}`\n")
L.append("## Headline\n")
L.append(f"**{headline}**\n")
L.append("| Metric | Count |")
L.append("|---|---:|")
L.append(f"| Files analyzed | {totals['files']} |")
L.append(f"| Raw lines added | {totals['lines_added']} |")
L.append(f"| Raw lines removed | {totals['lines_removed']} |")
L.append(f"| **Real adds** | **{totals['real_added']}** |")
L.append(f"| **Real removes** | **{totals['real_removed']}** |")
L.append(f"| Moved (exact) | {totals['moved_exact']} |")
L.append(f"| Moved (fuzzy) | {totals['moved_fuzzy']} |\n")
L.append("## Verdict distribution\n")
L.append("| Verdict | Files |")
L.append("|---|---:|")
for v, c in sorted(vc.items(), key=lambda x: -x[1]):
    L.append(f"| {v} | {c} |")
L.append("")
L.append(f"## Top {top_n} files by impact\n")
L.append("| File | Verdict | Real +/- | Moved | Notes |")
L.append("|---|---|---:|---:|---|")
for r in sorted_r[:top_n]:
    L.append(f"| `{r['file']}` | {r['verdict']} | +{r['real_added']}/-{r['real_removed']} | "
             f"{r['moved_exact']+r['moved_fuzzy']} | {r['notes']} |")
L.append("")
L.append("## By extension\n")
L.append("| Extension | Files | Real +/- | Moved |")
L.append("|---|---:|---:|---:|")
for e, s in sorted(ext.items(), key=lambda x: -(x[1]['real_added']+x[1]['real_removed'])):
    L.append(f"| .{e} | {s['files']} | +{s['real_added']}/-{s['real_removed']} | "
             f"{s['moved_exact']+s['moved_fuzzy']} |")
L.append("\n---\n*Generated by branch-real-diff v3*")
open(out_path,"w").write("\n".join(L))
PYMD
fi

# ====================== STDOUT SUMMARY ======================
python3 - "$RESULT" "$TOP_N" "$NO_COLOR" "$RANGE_DESC" <<'PYSTDOUT'
import json, sys
data = json.load(open(sys.argv[1]))
top_n, no_color, range_desc = int(sys.argv[2]), sys.argv[3]=="1", sys.argv[4]

if no_color or not sys.stdout.isatty():
    R=G=Y=B=BOLD=DIM=NC=""
else:
    R="\033[31m"; G="\033[32m"; Y="\033[33m"; B="\033[34m"
    BOLD="\033[1m"; DIM="\033[2m"; NC="\033[0m"

t = data["totals"]
print(f"{BOLD}══════════════════════════════════════════════════════════{NC}")
print(f"{BOLD} Branch Diff Analysis{NC}")
print(f" Range: {DIM}{range_desc}{NC}")
print(f"{BOLD}══════════════════════════════════════════════════════════{NC}\n")
print(f" Files analyzed:           {t['files']}")
print(f" Raw lines added/removed:  +{t['lines_added']} / -{t['lines_removed']}")
print(f" {BOLD}Real changes:{NC}             {R}+{t['real_added']}{NC} / {R}-{t['real_removed']}{NC}")
print(f" Moved (exact):            {Y}{t['moved_exact']}{NC}")
print(f" Moved (fuzzy):            {Y}{t['moved_fuzzy']}{NC}\n")

if t["real_added"]==0 and t["real_removed"]==0:
    print(f"{G}🟢 No REAL content differences — diff is pure rearrangement.{NC}")
else:
    print(f"{R}🔴 REAL differences detected.{NC}")
print()

print(f"{BOLD}Top {top_n} files by impact:{NC}")
sr = sorted(data["results"], key=lambda r: (-(r["real_added"]+r["real_removed"]),
                                            -(r["moved_exact"]+r["moved_fuzzy"])))
for r in sr[:top_n]:
    if r["verdict"]=="REAL": col=R
    elif r["verdict"] in ("MOVED","MOVED_IN","MOVED_OUT","REARRANGED","REFACTORED","RENAME_REFACTORED"): col=Y
    elif r["verdict"]=="BINARY": col=B
    else: col=G
    print(f"  {col}{r['verdict']:<22}{NC} {DIM}+{r['real_added']:<4} -{r['real_removed']:<4} "
          f"~{r['moved_exact']+r['moved_fuzzy']:<4}{NC} {r['file']}")
PYSTDOUT

echo
echo "${C_DIM}📄 CSV:      $OUTPUT${C_NC}"
[[ "$MARKDOWN" != "none" ]] && echo "${C_DIM}📝 Markdown: $MARKDOWN${C_NC}"

HAS_REAL=$(python3 -c "import json; d=json.load(open('$RESULT')); print(1 if d['totals']['real_added']>0 or d['totals']['real_removed']>0 else 0)")
exit "$HAS_REAL"
