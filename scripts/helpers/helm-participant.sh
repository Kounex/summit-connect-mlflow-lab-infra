#!/usr/bin/env bash
# One Helm invocation shared by preview, validation and installation.
set -euo pipefail
cd -- "$(dirname -- "$0")/../.."
participant=${1:?Supply userN}
mode=${2:?Supply render, dry-run or apply}
[[ $participant =~ ^user([1-9]|[1-4][0-9]|50)$ ]]
commit=$(jq -er .commit config/source.lock.json)
[[ $(cat .cache/SOURCE_COMMIT) == "$commit" ]]
chart=.cache/chart-$commit
values=(-f "$chart/values-multi-user.yaml" -f config/site-values.yaml -f .cache/image-values.yaml
  --set-string "workbench.name=$participant" --set-string "workbench.username=$participant"
  --set-string "workbench.repoRef=$commit" --set-string workbench.sourceConfigMap=workshop-source)
case "$mode" in
  lint) helm lint "$chart" "${values[@]}" ;;
  render) helm template tableschnappi "$chart" -n "tableschnappi-$participant" "${values[@]}" ;;
  dry-run) helm upgrade --install tableschnappi "$chart" -n "tableschnappi-$participant" "${values[@]}" --dry-run=server ;;
  apply) helm upgrade --install tableschnappi "$chart" -n "tableschnappi-$participant" "${values[@]}" --wait --timeout 15m ;;
  *) echo 'Expected render, dry-run or apply' >&2; exit 1 ;;
esac
