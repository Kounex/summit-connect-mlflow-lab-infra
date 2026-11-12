#!/usr/bin/env bash
# Native warmup Job. Empty baseline policy allows both cases; active policy blocks off-topic.
set -euo pipefail
if [[ ${1:-} == --help ]]; then
  echo "Usage: $0 [--expect-blocked] START END"; exit 0
fi
expected=false
if [[ ${1:-} == --expect-blocked ]]; then expected=true; shift; fi
[[ $# == 2 ]] || { echo 'Supply explicit START END' >&2; exit 1; }
cd -- "$(dirname -- "$0")/.."
source scripts/helpers/participants.sh
participant_range "$@"
source scripts/helpers/check-target.sh
image=$(awk -F= '$1=="ASSISTANT_IMAGE" { print substr($0,index($0,"=")+1) }' config/images.params)
for ((number=first_participant; number<=last_participant; number++)); do
  participant=$(printf 'user%d' "$number")
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
done
