#!/usr/bin/env bash
# Deliberate Secret boundary. Pass a private key file, never a key on the command line.
set -euo pipefail
cd -- "$(dirname -- "$0")/../.."
source scripts/helpers/check-target.sh
participant_name "${1:-}"
key_file=${2:?Usage: model-secret.sh user1 /private/path/api-key}
[[ -f $key_file && -s $key_file ]]
mode=${3:-apply}
[[ $mode == apply || $mode == dry-run ]]
apply_flags=(--server-side --field-manager=darmstadt-demo)
if [[ $mode == dry-run ]]; then apply_flags+=(--dry-run=server); fi
namespace=tableschnappi-$1
owned_namespace "$namespace"
if [[ -n $(oc get secret endpoint-api-key-1 -n "$namespace" --ignore-not-found -o name) ]]; then
  [[ $(oc get secret endpoint-api-key-1 -n "$namespace" -o jsonpath='{.metadata.labels.event\.redhat\.com/owner}') == darmstadt-demo ]]
fi
oc create secret generic endpoint-api-key-1 -n "$namespace" \
  --from-file="api_key=$key_file" --dry-run=client -o yaml |
  oc label --local -f - event.redhat.com/owner=darmstadt-demo -o yaml |
  oc apply "${apply_flags[@]}" -f -
