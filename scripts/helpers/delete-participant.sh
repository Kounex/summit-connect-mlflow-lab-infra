#!/usr/bin/env bash
# Removes the user's restaurant + workbench; shared MLflow history is retained.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
source "$ROOT/scripts/helpers/check-target.sh"
[[ $# == 2 && $1 =~ ^user([1-9]|[1-4][0-9]|50)$ && $2 == --destroy-participant-data ]] || {
  echo "Usage: $0 user1 --destroy-participant-data" >&2; exit 1;
}
participant=$1
namespace=tableschnappi-$participant
if [[ -n $(oc get ns "$namespace" --ignore-not-found -o name) ]]; then
[[ $(oc get ns "$namespace" -o jsonpath='{.metadata.labels.event\.redhat\.com/owner}') == darmstadt-demo ]] || {
  echo "Namespace is not demo-owned; refusing deletion" >&2; exit 1;
}
oc delete nemoguardrails tableschnappi-guardrails -n "$namespace" --ignore-not-found --wait=true --timeout=180s
oc delete notebook "$participant" -n "$namespace" --ignore-not-found --wait=true --timeout=120s
oc delete namespace "$namespace" --wait=true --timeout=300s
fi
# This binding lives outside the participant namespace and is explicitly owned.
binding=restaurant-image-puller-$participant
if [[ -n $(oc get ns tableschnappi-demo --ignore-not-found -o name) ]]; then
  if [[ -n $(oc get rolebinding "$binding" -n tableschnappi-demo --ignore-not-found -o name) ]]; then
    [[ $(oc get rolebinding "$binding" -n tableschnappi-demo -o jsonpath='{.metadata.labels.event\.redhat\.com/participant}') == "$participant" ]]
    [[ $(oc get rolebinding "$binding" -n tableschnappi-demo -o jsonpath='{.metadata.labels.event\.redhat\.com/owner}') == darmstadt-demo ]]
    oc delete rolebinding "$binding" -n tableschnappi-demo
  fi
fi
