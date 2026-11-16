#!/usr/bin/env bash
# Shared allowlist, target selection and bounded batches. Source from repo root.
participant_name() {
  [[ ${1:-} =~ ^(test|user([1-9]|[1-4][0-9]|50))$ ]] || {
    echo 'Expected user1 through user50, or test.' >&2; exit 1;
  }
}
participant_selection() {
  participants=()
  if [[ $# == 1 && $1 == --test ]]; then participants=(test); return; fi
  [[ $# == 0 || $# == 2 ]] || { echo 'Provide START END, --test, or neither.' >&2; exit 1; }
  local count first last number
  count=$(jq -er '.participantCount' config/source.lock.json)
  [[ $count =~ ^[0-9]{1,2}$ ]] || { echo 'Invalid participantCount.' >&2; exit 1; }
  count=$((10#$count))
  [[ $count -ge 1 && $count -le 50 ]] || { echo 'participantCount must be 1..50.' >&2; exit 1; }
  first=${1:-1}; last=${2:-$count}
  [[ $first =~ ^[0-9]{1,2}$ && $last =~ ^[0-9]{1,2}$ ]] || { echo 'START and END must be numbers.' >&2; exit 1; }
  first=$((10#$first)); last=$((10#$last))
  [[ $first -ge 1 && $first -le $last && $last -le $count ]] || {
    echo "Expected 1 <= START <= END <= $count." >&2; exit 1;
  }
  for ((number=first; number<=last; number++)); do participants+=("user$number"); done
}
_wait_participant_jobs() {
  local pid failed=0
  for pid in "$@"; do wait "$pid" || failed=1; done
  return "$failed"
}
participant_batch() {
  local concurrency=${1:?Supply concurrency}; shift
  [[ $concurrency =~ ^[1-8]$ ]] || { echo 'Concurrency must be 1..8.' >&2; exit 1; }
  local participant
  local pids=()
  for participant in "${participants[@]}"; do
    "$@" "$participant" &
    pids+=("$!")
    if [[ ${#pids[@]} == "$concurrency" ]]; then
      _wait_participant_jobs "${pids[@]}" || return 1
      pids=()
    fi
  done
  if [[ ${#pids[@]} -gt 0 ]]; then _wait_participant_jobs "${pids[@]}"; fi
}
