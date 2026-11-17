#!/usr/bin/env bash
# Wait for native controllers and credential consumers after the apply phase.
set -euo pipefail
cd -- "$(dirname -- "$0")/../.."
source scripts/helpers/check-target.sh
participant=${1:?Supply participant}; revision=${2:?Supply revision}
participant_name "$participant"
namespace=tableschnappi-$participant
owned_namespace "$namespace"
deadline=$((SECONDS + 300))
until oc get "statefulset/$participant" deployment/tableschnappi-guardrails -n "$namespace" -o json |
  jq -e --arg revision "$revision" '(.items | length) == 2 and all(.items[]; any(.spec.template.spec.containers[]?.env[]?; .name == "TABLESCHNAPPI_MODEL_REVISION" and .value == $revision))' > /dev/null; do
  [[ $SECONDS -lt $deadline ]] || { echo "$participant: controller did not observe model revision" >&2; exit 1; }
  sleep 2
done
for workload in deployment/tableschnappi-mlflow-proxy deployment/tableschnappi-guardrails "statefulset/$participant"; do
  oc rollout status "$workload" -n "$namespace" --timeout=600s
done
oc exec -i "$participant-0" -c "$participant" -n "$namespace" -- python - "$revision" <<'PY'
import os,requests,sys
assert os.environ['TABLESCHNAPPI_MODEL_REVISION'] == sys.argv[1]
response=requests.post(os.environ['GUARDRAILS_URL']+'/v1/chat/completions',json={
 'model':os.environ['MODEL_NAME'],'messages':[{'role':'user','content':'What is on your menu?'}],
 'max_tokens':1},timeout=180)
response.raise_for_status()
print('NeMo warmup HTTP',response.status_code,flush=True)
PY
printf '%s model rollout complete\n' "$participant"
