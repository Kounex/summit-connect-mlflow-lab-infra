#!/usr/bin/env bash
# Entry: apply Git BuildConfigs, build five components, and record their digests.
set -euo pipefail
if [[ ${1:-} == --help ]]; then
  echo "Usage: $0 (builds the pinned source on the selected cluster; see README step 3)"; exit 0
fi
[[ $# == 0 ]] || { echo "Usage: $0" >&2; exit 1; }
cd -- "$(dirname -- "$0")/.."
source scripts/helpers/check-target.sh
owned_namespace tableschnappi-demo
oc apply --server-side --field-manager=darmstadt-demo -f manifests/10-images/builds.yaml
builds=()
for component in frontend backend mcp mlflow-proxy workbench; do
  builds+=("$(oc start-build "tableschnappi-$component" -n tableschnappi-demo -o name)")
done
for build in "${builds[@]}"; do
  deadline=$((SECONDS + 1200))
  while :; do
    phase=$(oc get "$build" -n tableschnappi-demo -o jsonpath='{.status.phase}')
    case "$phase" in
      Complete) echo "$build Complete"; break ;;
      Failed|Error|Cancelled) echo "$build $phase; inspect oc logs $build -n tableschnappi-demo" >&2; exit 1 ;;
    esac
    [[ $SECONDS -lt $deadline ]] || { echo "$build timed out in $phase" >&2; exit 1; }
    sleep 3
  done
done
bash scripts/helpers/lock-images.sh
