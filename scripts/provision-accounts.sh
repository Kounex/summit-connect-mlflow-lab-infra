#!/usr/bin/env bash
# Optional entry for clusters using an existing operator-managed Keycloak IDP.
set -euo pipefail
if [[ ${1:-} == --help ]]; then
  echo "Usage: $0 [--delete-owned-accounts] /absolute/private-directory START END"
  echo 'Create a range of accounts, or delete only accounts recorded as created here.'
  echo 'Demo passwords match usernames (user1:user1). Reruns reset recorded accounts to this convention.'
  echo 'Ownership receipts stay outside this repository.'
  exit 0
fi
mode=create
if [[ ${1:-} == --delete-owned-accounts ]]; then mode=delete; shift; fi
[[ $# == 3 && $1 == /* ]] || { echo 'Supply an absolute private output directory and explicit START END.' >&2; exit 1; }
private_dir=$1; shift
cd -- "$(dirname -- "$0")/.."
source scripts/helpers/participants.sh
participant_range "$@"
source scripts/helpers/check-target.sh
python3 scripts/helpers/keycloak-accounts.py "$mode" "$private_dir" "$first_participant" "$last_participant"
