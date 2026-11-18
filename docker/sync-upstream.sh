#!/usr/bin/env bash
set -euo pipefail

# Apply upstream source changes without importing upstream workflow commits.
# GITHUB_TOKEN has contents:write, but cannot import workflow-file updates.
upstream_url=${UPSTREAM_URL:-https://github.com/MetaCubeX/metacubexd.git}
branch=${SYNC_BRANCH:-main}
state_file=docker/upstream-source.sha
git check-ref-format "refs/heads/$branch"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo 'Synchronization requires a clean index and working tree.' >&2
  exit 1
fi
git fetch --no-tags "$upstream_url" "$branch"
upstream_sha=$(git rev-parse FETCH_HEAD)
if [[ -f "$state_file" ]]; then
  base_sha=$(cat "$state_file")
  git cat-file -e "$base_sha^{commit}"
else
  base_sha=$(git merge-base HEAD "$upstream_sha")
fi

patch=$(mktemp)
trap 'rm -f "$patch"' EXIT
git diff --binary --full-index "$base_sha" "$upstream_sha" -- . ':(exclude).github/workflows/**' > "$patch"
if [[ -s "$patch" ]] && ! git apply --3way --index "$patch"; then
  # The clean-tree precondition makes this rollback safe for fork changes.
  git restore --source=HEAD --staged --worktree -- .
  echo 'Upstream source conflicts with fork changes. The remote fork was not overwritten.' >&2
  exit 1
fi

mkdir -p "$(dirname "$state_file")"
printf '%s\n' "$upstream_sha" > "$state_file"
git add "$state_file"
if ! git diff --cached --quiet; then
  git -c user.name='github-actions[bot]' \
      -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
      commit -m "chore: sync upstream source $upstream_sha"
fi

sha=$(git rev-parse HEAD)
git push origin "HEAD:refs/heads/$branch"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'sha=%s\nupstream_sha=%s\n' "$sha" "$upstream_sha" >> "$GITHUB_OUTPUT"
fi
printf 'Synchronized fork %s with upstream source %s; fork workflows retained.\n' "$sha" "$upstream_sha"
