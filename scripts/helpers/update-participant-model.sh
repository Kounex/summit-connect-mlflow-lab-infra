#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/../.."
source scripts/helpers/check-target.sh
participant=${1:?Supply participant}; key_file=${2:?Supply key file}
values_file=${3:?Supply model values}; export MODEL_REVISION=${4:?Supply model revision}
participant_name "$participant"
namespace=tableschnappi-$participant
owned_namespace "$namespace"
helm status tableschnappi -n "$namespace" > /dev/null
helm get values tableschnappi -n "$namespace" -o yaml > "$MODEL_BACKUP_DIR/$participant-values.yaml"
oc get secret endpoint-api-key-1 -n "$namespace" -o yaml > "$MODEL_BACKUP_DIR/$participant-model-secret.yaml"
oc get configmap tableschnappi-guardrails-config -n "$namespace" -o yaml > "$MODEL_BACKUP_DIR/$participant-guardrails.yaml"
bash scripts/helpers/model-secret.sh "$participant" "$key_file"
export MODEL_NAMESPACE=$namespace
commit=$(jq -er .commit config/source.lock.json)
flags=()
if [[ $(helm version --short) == v4.* ]]; then flags+=(--server-side=false); fi
helm upgrade tableschnappi ".cache/chart-$commit" -n "$namespace" \
  "${flags[@]}" --reuse-values -f "$values_file" \
  --post-renderer "$MODEL_POST_RENDERER" --no-hooks --timeout 10m
printf '%s model configuration applied\n' "$participant"
