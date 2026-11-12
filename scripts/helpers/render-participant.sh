#!/usr/bin/env bash
# Preview all project/config/app objects. Helm hook order is handled during install.
set -euo pipefail
cd -- "$(dirname -- "$0")/../.."
participant=${1:?Supply userN}
[[ $participant =~ ^user([1-9]|[1-4][0-9]|50)$ ]]
source scripts/helpers/participant-yaml.sh
emit() { printf '%s\n' '---'; "$@"; }
for template in manifests/30-participant/project/*.yaml; do
  emit participant_template "$participant" "$template"
done
emit participant_source "$participant"
emit bash scripts/helpers/helm-participant.sh "$participant" render
