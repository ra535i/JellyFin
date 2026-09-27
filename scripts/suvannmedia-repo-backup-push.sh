#!/bin/bash
# Push committed source only. This refuses a dirty tree rather than silently
# committing runtime configuration, credentials, or an accidental secret.
set -euo pipefail

REPO=/home/skim/JellyFin
cd "$REPO"

if ! git diff --quiet || ! git diff --cached --quiet || \
   test -n "$(git ls-files --others --exclude-standard)"; then
  echo 'ERROR: repository is dirty; review and commit intended source changes before backup push.' >&2
  git status --short >&2
  exit 3
fi

git fetch --quiet origin main
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" = "$REMOTE" ]; then
  echo "Repository backup current at $LOCAL"
  exit 0
fi

if git merge-base --is-ancestor "$REMOTE" "$LOCAL"; then
  git push origin main
  echo "Repository backup pushed: $LOCAL"
  exit 0
fi

echo "ERROR: origin/main is ahead or diverged; refusing to overwrite remote history." >&2
exit 4
