#!/usr/bin/env bash
# ============================================================================
# sync_scripts.sh — refresh this repo's committed driver/runner scripts from the
# live project working dir (the repo is the canonical source of truth; we develop
# live then sync stable scripts back in).
#
# It copies the working-dir version OVER every script ALREADY TRACKED in the repo,
# matched by basename — so it never has to know the bin/ vs experiments/ vs
# annotation/ placement (that classification is fixed once, at `git add` time).
# NEW scripts are added by hand the first time (placed + `git add`), then this
# keeps them in sync. Only code is touched; data never (basename match is limited
# to tracked script paths, and .gitignore is the backstop).
#
# Usage:   PROJECT=/path/to/working_dir  bin/sync_scripts.sh
#          (PROJECT defaults to the S. cameroni project root)
# Then review `git status`/`git diff` and commit.
# ============================================================================
set -euo pipefail
PROJECT="${PROJECT:-/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$PROJECT" ] || { echo "PROJECT not found: $PROJECT" >&2; exit 1; }

# Working-dir files that are intentionally DIFFERENT from the repo (thin shims that
# delegate INTO the repo) — never overwrite the real repo versions with these.
SKIP_BASENAMES=" run_pipeline.sh run_annotation.sh "

copied=0 skipped=0 nosrc=0
while IFS= read -r repofile; do
  base="$(basename "$repofile")"
  case "$SKIP_BASENAMES" in *" $base "*) skipped=$((skipped+1)); continue;; esac
  # find the working-dir source by basename, excluding the repo subtree itself
  src="$(find "$PROJECT" -path "$PROJECT/$(basename "$REPO")" -prune -o -name "$base" -print 2>/dev/null | head -1)"
  if [ -z "$src" ]; then
    echo "  no working-dir source for tracked $repofile" >&2; nosrc=$((nosrc+1)); continue
  fi
  if ! diff -q "$src" "$REPO/$repofile" >/dev/null 2>&1; then
    cp "$src" "$REPO/$repofile" && echo "  updated $repofile  <-  $src"; copied=$((copied+1))
  fi
done < <(cd "$REPO" && git ls-files \
    'bin/*.sh' 'bin/*.py' 'annotation/**/*.sh' 'annotation/**/*.py' \
    'cluster/*' 'experiments/*')

echo "sync: $copied updated, $skipped shims skipped, $nosrc tracked-but-no-source"
echo "---- git status ----"; (cd "$REPO" && git status -s)
