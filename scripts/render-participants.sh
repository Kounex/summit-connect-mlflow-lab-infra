#!/usr/bin/env bash
# Entry: preview processed participant YAML on stdout; no per-user directories.
set -euo pipefail
if [[ ${1:-} == --help ]]; then
  echo "Usage: $0 [START END] > /tmp/participants.yaml"
  echo 'Default: preview the configured roster. No generated YAML folders or cluster writes.'
  exit 0
fi
cd -- "$(dirname -- "$0")/.."
source scripts/helpers/participants.sh
participant_range "$@"
bash scripts/helpers/prepare-workbench-source.sh >&2
bash scripts/helpers/image-values.sh > .cache/image-values.yaml
for ((number=first_participant; number<=last_participant; number++)); do
  participant=$(printf 'user%d' "$number")
  bash scripts/helpers/render-participant.sh "$participant"
done
