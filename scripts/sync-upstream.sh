#!/usr/bin/env bash
#
# Re-derive this fork's filtered upstream history from zed-industries/zed and
# advance the local `upstream` branch to it.
#
# This fork is a PATH-FILTERED extraction of the Zed monorepo (the crates listed
# in scripts/upstream-paths.txt), not a whole-repo fork, so "sync" is not a plain
# `git fetch`: upstream's history has to be re-filtered, which reproduces the
# commits already published here and appends the new ones.
#
# That reproduction is exact only if the extraction is byte-for-byte the same
# every time, which is why two things are pinned and neither is cosmetic:
#
#   * scripts/upstream-paths.txt — the path set. Change it and EVERY commit gets
#     a new SHA.
#   * --preserve-commit-hashes  — without it git-filter-repo rewrites commit
#     SHAs that appear inside commit MESSAGES, and what a given SHA rewrites to
#     depends on which refs happened to be in the clone. Measured on this repo:
#     the same upstream commit came out as 6e528fc5 from a full mirror and
#     18d8ff18 from a main-only clone, purely because one message said
#     "Brings commit <sha> back". Every commit after it then diverged too.
#
# The script never trusts that reasoning on its own: it re-derives the history
# and REFUSES to move `upstream` unless the branch's current tip is an ancestor
# of what came out. A failure there means the extraction inputs changed
# (edited path list, upstream force-push, or a git-filter-repo whose output
# differs) and that a merge would replay the whole history as new commits.
#
# Usage:
#   scripts/sync-upstream.sh              # refresh the `upstream` branch only
#   scripts/sync-upstream.sh --merge      # ...then merge it into the current branch
#
# Environment: UPSTREAM_URL, UPSTREAM_BRANCH, KEEP_WORKDIR=1
#
# Requirements: git-filter-repo on PATH (`pip install git-filter-repo`), network
# access to GitHub, and ~3 GB of free disk — filter-repo needs real blobs, so the
# upstream clone cannot be a blobless one (~1.3 GB for zed at the time of writing).

set -euo pipefail

UPSTREAM_URL=${UPSTREAM_URL:-https://github.com/zed-industries/zed}
UPSTREAM_BRANCH=${UPSTREAM_BRANCH:-main}
MERGE=0
[ "${1:-}" = "--merge" ] && MERGE=1

die() { printf '\nsync-upstream: %s\n' "$*" >&2; exit 1; }

command -v git-filter-repo >/dev/null 2>&1 \
  || die "git-filter-repo not found on PATH. Install it with: pip install git-filter-repo"

ROOT=$(git rev-parse --show-toplevel) || die "not inside a git checkout"
PATHS_FILE="$ROOT/scripts/upstream-paths.txt"
[ -f "$PATHS_FILE" ] || die "missing $PATHS_FILE"

git -C "$ROOT" diff --quiet && git -C "$ROOT" diff --cached --quiet \
  || die "working tree has uncommitted changes; commit or stash them first"

mapfile -t PATHS < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$PATHS_FILE" | grep -v '^$')
[ "${#PATHS[@]}" -gt 0 ] || die "$PATHS_FILE lists no paths"
FILTER_ARGS=()
for p in "${PATHS[@]}"; do FILTER_ARGS+=(--path "$p"); done

WORK=$(mktemp -d "${TMPDIR:-/tmp}/gpui-sync.XXXXXX")
cleanup() { [ "${KEEP_WORKDIR:-0}" = "1" ] || rm -rf "$WORK"; }
trap cleanup EXIT

echo "==> cloning $UPSTREAM_URL ($UPSTREAM_BRANCH) — this pulls the full Zed repo"
git clone --single-branch --no-tags --branch "$UPSTREAM_BRANCH" "$UPSTREAM_URL" "$WORK/zed"
UPSTREAM_TIP=$(git -C "$WORK/zed" rev-parse HEAD)
echo "==> upstream tip: $UPSTREAM_TIP"

echo "==> filtering to ${#PATHS[@]} paths (git-filter-repo $(git-filter-repo --version 2>/dev/null || echo '?'))"
git -C "$WORK/zed" filter-repo --force --preserve-commit-hashes "${FILTER_ARGS[@]}"

git -C "$ROOT" fetch --no-tags "$WORK/zed" "+refs/heads/$UPSTREAM_BRANCH:refs/upstream-sync/candidate"
NEW=$(git -C "$ROOT" rev-parse refs/upstream-sync/candidate)
drop_candidate() { git -C "$ROOT" update-ref -d refs/upstream-sync/candidate || true; }

# A fresh clone has no local `upstream` branch, only origin's. Fall back to it,
# or the ancestry check below would be skipped on exactly the checkout most
# likely to be running this for the first time.
OLD=$(git -C "$ROOT" rev-parse --verify -q refs/heads/upstream \
   || git -C "$ROOT" rev-parse --verify -q refs/remotes/origin/upstream || true)
if [ -n "$OLD" ]; then
  if [ "$OLD" = "$NEW" ]; then
    echo "==> already up to date ($OLD)"
    drop_candidate
    exit 0
  fi
  if ! git -C "$ROOT" merge-base --is-ancestor "$OLD" "$NEW"; then
    drop_candidate
    die "re-derived history does NOT contain the published \`upstream\` tip $OLD.
       Advancing would replace every commit with a differently-hashed twin and
       nothing already pinned would merge. Something in the extraction changed:
       scripts/upstream-paths.txt, the git-filter-repo version, or upstream's
       own history. Investigate before touching \`upstream\`."
  fi
  echo "==> $(git -C "$ROOT" rev-list --count "$OLD..$NEW") new upstream commits since $OLD"
else
  echo "==> creating \`upstream\` at $NEW"
fi

git -C "$ROOT" update-ref refs/heads/upstream "$NEW"
drop_candidate
echo "==> upstream -> $NEW  (upstream/zed $UPSTREAM_TIP)"

if [ "$MERGE" = "0" ]; then
  cat <<EOF

Next: merge it into your branch and re-prune the manifest.

    git merge upstream
    # on a Cargo.toml conflict, take upstream's members list, then:
    python3 scripts/prune-workspace.py && git add Cargo.toml && git commit

EOF
  exit 0
fi

BRANCH=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)
echo "==> merging \`upstream\` into $BRANCH"
if git -C "$ROOT" merge --no-edit upstream; then
  python3 "$ROOT/scripts/prune-workspace.py" --check >/dev/null \
    || die "merge succeeded but Cargo.toml is no longer pruned — run
       python3 scripts/prune-workspace.py, then amend the merge commit."
  echo "==> merged cleanly"
  exit 0
fi

if git -C "$ROOT" diff --name-only --diff-filter=U | grep -qx 'Cargo.toml'; then
  echo "==> resolving Cargo.toml from upstream's side + prune-workspace.py"
  git -C "$ROOT" checkout --theirs -- Cargo.toml
  python3 "$ROOT/scripts/prune-workspace.py"
  git -C "$ROOT" add Cargo.toml
fi

REMAINING=$(git -C "$ROOT" diff --name-only --diff-filter=U)
if [ -n "$REMAINING" ]; then
  echo
  echo "Conflicts left for you (the MGVS patch vs upstream's changes):"
  echo "$REMAINING" | sed 's/^/    /'
  echo
  echo "Resolve, then: git commit"
  exit 1
fi

git -C "$ROOT" commit --no-edit
echo "==> merged (Cargo.toml resolved automatically)"
