#!/bin/bash
set -euo pipefail

# Delete local git branches whose last commit is older than 2 months.
# Protects: current branch, main, master, develop, qa, stage.
# Safe to run multiple times (already-deleted branches are skipped).

PROTECTED_BRANCHES="main master develop qa stage pre-prod-validation"
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

# Calculate cutoff date in a cross-platform way (works on macOS/BSD and Linux/GNU)
if date -v-2m +%Y-%m-%d > /dev/null 2>&1; then
  # macOS / BSD date
  TWO_MONTHS_AGO=$(date -v-2m +%Y-%m-%d)
else
  # GNU date (Linux)
  TWO_MONTHS_AGO=$(date -d "2 months ago" +%Y-%m-%d)
fi

echo "Cutoff date: $TWO_MONTHS_AGO (branches with last commit before this will be deleted)"
echo ""

DELETED=0
SKIPPED=0

# Use array-safe branch listing (handles whitespace, strips leading * and spaces)
while IFS= read -r raw_branch; do
  branch="${raw_branch#\* }"   # strip current-branch marker
  branch="${branch#  }"        # strip leading spaces
  branch="${branch%%[[:space:]]*}" # strip trailing spaces

  [ -z "$branch" ] && continue

  # Skip current branch
  if [ "$branch" = "$CURRENT_BRANCH" ]; then
    echo "SKIP $branch (current branch)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Skip protected branches
  is_protected=0
  for protected in $PROTECTED_BRANCHES; do
    if [ "$branch" = "$protected" ]; then
      is_protected=1
      break
    fi
  done
  if [ "$is_protected" -eq 1 ]; then
    echo "SKIP $branch (protected)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Get last commit date for this branch
  last_modified=$(git log -1 --date=short --pretty=format:"%cd" "$branch" 2>/dev/null || echo "")
  if [ -z "$last_modified" ]; then
    echo "SKIP $branch (could not determine last commit date)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if [[ "$last_modified" < "$TWO_MONTHS_AGO" ]]; then
    echo "DELETE $branch (last commit: $last_modified)"
    git branch -d "$branch" || git branch -D "$branch"
    DELETED=$((DELETED + 1))
  else
    echo "KEEP $branch (last commit: $last_modified)"
  fi
done < <(git branch --list)

echo ""
echo "Done. Deleted: $DELETED, Skipped: $SKIPPED"
