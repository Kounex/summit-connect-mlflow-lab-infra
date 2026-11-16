#!/usr/bin/env bash
# One namespace's native warmup Job; invoked by the batch entry.
set -euo pipefail
cd -- "$(dirname -- "$0")/../.."
source scripts/helpers/check-target.sh
participant=${1:?Supply participant}
participant_name "$participant"
image=${2:?Supply image}
expected=${3:?Supply expected policy}
namespace=tableschnappi-$participant
owned_namespace "$namespace"
model=$(oc get deployment tableschnappi-mlflow-proxy -n "$namespace" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="VLLM_MODEL")].value}')
[[ -n $model ]]
oc rollout status deployment/tableschnappi-guardrails -n "$namespace" --timeout=600s
if [[ -n $(oc get job guardrails-warmup -n "$namespace" --ignore-not-found -o name) ]]; then
  [[ $(oc get job guardrails-warmup -n "$namespace" -o jsonpath='{.metadata.labels.event\.redhat\.com/owner}') == darmstadt-demo ]]
  oc delete job guardrails-warmup -n "$namespace" --wait=true
fi
oc process --local -f manifests/90-operations/guardrails-warmup.yaml \
  -p "PARTICIPANT=$participant" -p "ASSISTANT_IMAGE=$image" -p "MODEL_NAME=$model" -p "EXPECT_BLOCKED=$expected" -o yaml |
  oc apply --server-side --field-manager=darmstadt-demo -f -
oc wait job/guardrails-warmup -n "$namespace" --for=condition=Complete --timeout=480s
oc logs job/guardrails-warmup -n "$namespace"
