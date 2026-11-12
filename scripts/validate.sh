#!/usr/bin/env bash
# Local rendering checks only; server admission is checked by apply --dry-run.
set -euo pipefail
if [[ ${1:-} == --help ]]; then
  echo "Usage: $0 [START END] (local project/Helm rendering checks)"; exit 0
fi
cd -- "$(dirname -- "$0")/.."
source scripts/helpers/participants.sh
source scripts/helpers/participant-yaml.sh
participant_range "$@"
bash scripts/helpers/prepare-workbench-source.sh >&2
bash scripts/helpers/image-values.sh > .cache/image-values.yaml
bash scripts/helpers/helm-participant.sh user1 lint
for ((number=first_participant; number<=last_participant; number++)); do
  participant=$(printf 'user%d' "$number")
  namespace=tableschnappi-$participant
  for template in manifests/30-participant/project/*.yaml; do
    oc process --local -f "$template" -p "PARTICIPANT=$participant" -o json |
      jq -e --arg ns "$namespace" 'all(.items[]; if .kind == "Namespace" then .metadata.name == $ns elif .kind == "RoleBinding" then .metadata.namespace == "tableschnappi-demo" else .metadata.namespace == $ns end)' >/dev/null
  done
  bash scripts/helpers/helm-participant.sh "$participant" render >/dev/null
  echo "$participant local project/chart rendering PASS"
done
