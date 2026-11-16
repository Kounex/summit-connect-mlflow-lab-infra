#!/usr/bin/env bash
# Read-only static and native workspace/MCP checks; creates no traces/model calls.
set -euo pipefail
if [[ ${1:-} == --help ]]; then
  echo "Usage: $0 [START END | --test]"
  echo 'CHECK_CONCURRENCY=1..8 (default 4). Uses existing workbench service accounts.'
  exit 0
fi
cd -- "$(dirname -- "$0")/.."
source scripts/helpers/participants.sh
participant_selection "$@"
source scripts/helpers/check-target.sh
check_one() {
  local participant=$1 namespace=tableschnappi-$1
  owned_namespace "$namespace"
  for workload in deployment/tableschnappi-frontend deployment/tableschnappi-backend deployment/tableschnappi-mcp deployment/tableschnappi-mlflow-proxy deployment/tableschnappi-guardrails "statefulset/$participant"; do
    oc rollout status "$workload" -n "$namespace" --timeout=60s > /dev/null
  done
  oc exec -i "$participant-0" -c "$participant" -n "$namespace" -- \
    python - "$namespace" "$(jq -er .commit config/source.lock.json)" < scripts/helpers/check-workbench.py
}
participant_batch "${CHECK_CONCURRENCY:-4}" check_one
