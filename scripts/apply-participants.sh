#!/usr/bin/env bash
# Entry: process templates into SSA/Helm with bounded batches; stop on error.
set -euo pipefail
if [[ ${1:-} == --help ]]; then
  echo "Usage: $0 [--dry-run] /absolute/model-key-file [START END | --test]"
  echo 'Default: apply the configured roster directly. --dry-run validates existing projects without writes.'
  exit 0
fi
mode=apply
if [[ ${1:-} == --dry-run ]]; then mode=dry-run; shift; fi
key_file=${1:?Usage: apply-participants.sh [--dry-run] /absolute/model-key-file [START END | --test]}
[[ $key_file == /* && -f $key_file && -s $key_file ]] || { echo 'Supply an absolute path to a nonempty private model-key file.' >&2; exit 1; }
shift
cd -- "$(dirname -- "$0")/.."
source scripts/helpers/participants.sh
participant_selection "$@"
source scripts/helpers/check-target.sh
bash scripts/helpers/prepare-workbench-source.sh >&2
bash scripts/helpers/image-values.sh > .cache/image-values.yaml
apply_one() {
  printf '%s %s\n' "$mode" "$1" >&2
  bash scripts/helpers/apply-participant.sh "$1" "$key_file" "$mode"
}
participant_batch "${APPLY_CONCURRENCY:-1}" apply_one
