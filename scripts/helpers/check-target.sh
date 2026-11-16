#!/usr/bin/env bash
# Source before cluster mutations. No default context or implicit cluster.
set -euo pipefail
: "${KUBECONFIG:?Set a dedicated kubeconfig outside this repository}"
: "${EXPECTED_API_SERVER:?Set the intended cluster API URL}"
[[ $(oc whoami --show-server) == "$EXPECTED_API_SERVER" ]] || {
  echo 'Cluster mismatch; stopping.' >&2; exit 1;
}
owned_namespace() {
  [[ $(oc get namespace "$1" -o jsonpath='{.metadata.labels.event\.redhat\.com/owner}') == darmstadt-demo ]] || {
    echo "Namespace $1 is not lab-owned; stopping." >&2; exit 1;
  }
}
source "$(dirname -- "${BASH_SOURCE[0]}")/participants.sh"
