#!/bin/bash

# Get the current date in the format YYYY-MM-DD
current_date=$(date +%Y-%m-%d)

# Calculate the date 2 months ago in the same format
two_months_ago=$(date -d "$current_date -2 months" +%Y-%m-%d)

# Get a list of all local branches
branches=$(git branch -l)

# Iterate over the list of branches
for branch in $branches; do
  # Get the date the branch was last modified in the format YYYY-MM-DD
  last_modified=$(git log -1 --date=short --pretty=format:"%cd" $branch)

  # Compare the date the branch was last modified to the date 2 months ago
  if [[ $last_modified < $two_months_ago ]]; then
    # If the branch was last modified before 2 months ago, delete it
    git branch -d $branch
  fi
done
