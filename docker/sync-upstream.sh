#!/usr/bin/env bash
set -euo pipefail

# Never reset or force-push: fork-only files must survive synchronization.
upstream_url=${UPSTREAM_URL:-https://github.com/MetaCubeX/metacubexd.git}
branch=${SYNC_BRANCH:-main}
git check-ref-format "refs/heads/$branch"
git fetch --no-tags "$upstream_url" "$branch"
upstream_sha=$(git rev-parse FETCH_HEAD)

if ! git -c user.name='github-actions[bot]' \
         -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
         merge --no-edit "$upstream_sha"; then
  git merge --abort || true
  echo 'Upstream merge failed. Resolve the conflict manually; the remote fork was not overwritten.' >&2
  exit 1
fi

sha=$(git rev-parse HEAD)
git push origin "HEAD:refs/heads/$branch"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'sha=%s\nupstream_sha=%s\n' "$sha" "$upstream_sha" >> "$GITHUB_OUTPUT"
fi
printf 'Synchronized fork %s with upstream %s\n' "$sha" "$upstream_sha"
