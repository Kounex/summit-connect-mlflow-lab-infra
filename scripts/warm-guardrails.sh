#!/usr/bin/env bash
# Native warmup Job. Empty baseline policy allows both cases; active policy blocks off-topic.
set -euo pipefail
if [[ ${1:-} == --help ]]; then
  echo "Usage: $0 [--expect-blocked] START END | --test"; exit 0
fi
expected=false
if [[ ${1:-} == --expect-blocked ]]; then expected=true; shift; fi
[[ $# == 2 || ( $# == 1 && $1 == --test ) ]] || { echo 'Supply explicit START END' >&2; exit 1; }
cd -- "$(dirname -- "$0")/.."
source scripts/helpers/participants.sh
participant_selection "$@"
source scripts/helpers/check-target.sh
image=$(awk -F= '$1=="ASSISTANT_IMAGE" { print substr($0,index($0,"=")+1) }' config/images.params)
warm_one() { bash scripts/helpers/warm-participant.sh "$1" "$image" "$expected"; }
participant_batch "${WARM_CONCURRENCY:-1}" warm_one
