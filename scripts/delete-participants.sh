#!/usr/bin/env bash
# Entry: explicit destructive range, with per-project target/ownership guards.
set -euo pipefail
if [[ ${1:-} == --help ]]; then
  echo "Usage: $0 --destroy-participant-data START END | --test (explicit range required)"
  echo 'DELETE_CONCURRENCY=1..8 controls independent deletions; default 1.'; exit 0
fi
[[ ( $# == 3 || $# == 2 ) && $1 == --destroy-participant-data ]] || {
  echo "Usage: $0 --destroy-participant-data START END | --test" >&2; exit 1;
}
shift
cd -- "$(dirname -- "$0")/.."
source scripts/helpers/participants.sh
participant_selection "$@"
delete_one() { bash scripts/helpers/delete-participant.sh "$1" --destroy-participant-data; }
participant_batch "${DELETE_CONCURRENCY:-1}" delete_one
