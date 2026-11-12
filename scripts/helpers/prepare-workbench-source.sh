#!/usr/bin/env bash
# Package exactly the audited source. No cluster writes and no moving checkout.
set -euo pipefail
cd -- "$(dirname -- "$0")/../.."
repository=$(jq -er .repository config/source.lock.json)
commit=$(jq -er .commit config/source.lock.json)
[[ $commit =~ ^[0-9a-f]{40}$ ]]
mkdir -p .cache
if [[ ! -d .cache/source/.git ]]; then
  git init -q .cache/source
  git -C .cache/source remote add origin "$repository"
fi
[[ $(git -C .cache/source remote get-url origin) == "$repository" ]]
git -C .cache/source fetch --depth=1 origin "$commit"
[[ $(git -C .cache/source rev-parse FETCH_HEAD) == "$commit" ]]
git -C .cache/source archive --format=tar "$commit" > .cache/source.tar
gzip -c .cache/source.tar > .cache/source.tar.gz
printf '%s\n' "$commit" > .cache/SOURCE_COMMIT
# ConfigMaps have a 1 MiB object limit including notebooks and base64 overhead.
[[ $(wc -c < .cache/source.tar.gz) -lt 700000 ]]
mkdir -p ".cache/chart-$commit"
tar xzf .cache/source.tar.gz -C ".cache/chart-$commit" --strip-components=2 charts/tableschnappi
echo 'Pinned source and Helm chart packaged in .cache; no cluster changes.'
