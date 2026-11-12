#!/usr/bin/env bash
# Entry: explicit destructive range, with per-project target/ownership guards.
set -euo pipefail
if [[ ${1:-} == --help ]]; then
  echo "Usage: $0 --destroy-participant-data START END (explicit range required)"
  echo 'DELETE_CONCURRENCY=1..8 controls independent deletions; default 1.'; exit 0
fi
[[ $# == 3 && $1 == --destroy-participant-data && -n $2 && -n $3 ]] || {
  echo "Usage: $0 --destroy-participant-data START END" >&2; exit 1;
}
shift
cd -- "$(dirname -- "$0")/.."
source scripts/helpers/participants.sh
participant_range "$@"
concurrency=${DELETE_CONCURRENCY:-1}
[[ $concurrency =~ ^[1-8]$ ]] || { echo 'DELETE_CONCURRENCY must be 1..8.' >&2; exit 1; }
pids=()
wait_batch() {
  local failed=0 pid
  for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
  pids=()
  return "$failed"
}
for ((number=first_participant; number<=last_participant; number++)); do
  participant=$(printf 'user%d' "$number")
  bash scripts/helpers/delete-participant.sh "$participant" --destroy-participant-data &
  pids+=("$!")
  if [[ ${#pids[@]} == "$concurrency" ]]; then wait_batch; fi
done
if [[ ${#pids[@]} -gt 0 ]]; then wait_batch; fi
