#!/usr/bin/env bash
# Native project/access YAML first; Helm owns the participant application/workbench.
set -euo pipefail
participant=${1:?Supply userN}
key_file=${2:?Supply an absolute private model-key file}
mode=${3:-apply}
[[ $key_file == /* && -f $key_file && -s $key_file ]]
[[ $mode == apply || $mode == dry-run ]]
cd -- "$(dirname -- "$0")/../.."
source scripts/helpers/check-target.sh
source scripts/helpers/participant-yaml.sh
participant_name "$participant"
owned_namespace tableschnappi-demo
namespace=tableschnappi-$participant
if [[ -n $(oc get namespace "$namespace" --ignore-not-found -o name) ]]; then
  owned_namespace "$namespace"
  if [[ -n $(oc get deployment tableschnappi-backend -n "$namespace" --ignore-not-found -o name) ]] &&
     ! helm status tableschnappi -n "$namespace" >/dev/null 2>&1; then
    echo "$namespace has the previous plain-YAML stack. Delete/recreate this demo participant before Helm installation." >&2
    exit 1
  fi
elif [[ $mode == dry-run ]]; then
  echo "Server dry-run needs existing $namespace; use render-participants.sh for a new project." >&2; exit 1
fi
apply_flags=(--server-side --field-manager=darmstadt-demo)
[[ $mode == apply ]] || apply_flags+=(--dry-run=server)
participant_template "$participant" manifests/30-participant/project/namespace.yaml | oc apply "${apply_flags[@]}" -f -
for template in manifests/30-participant/project/*.yaml; do
  [[ $template == */namespace.yaml ]] && continue
  participant_template "$participant" "$template" | oc apply "${apply_flags[@]}" -f -
done
bash scripts/helpers/model-secret.sh "$participant" "$key_file" "$mode"
participant_source "$participant" | oc apply "${apply_flags[@]}" -f -
bash scripts/helpers/helm-participant.sh "$participant" "$mode"
if [[ $mode == apply ]]; then
  for workload in "statefulset/$participant" deployment/tableschnappi-guardrails; do
    deadline=$((SECONDS + 300))
    until [[ -n $(oc get "$workload" -n "$namespace" --ignore-not-found -o name) ]]; do
      [[ $SECONDS -lt $deadline ]] || { echo "Controller did not create $workload" >&2; exit 1; }
      sleep 2
    done
    oc rollout status "$workload" -n "$namespace" --timeout=900s
  done
fi
