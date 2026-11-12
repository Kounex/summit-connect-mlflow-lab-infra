#!/usr/bin/env bash
# Resolve new-site build results; inspect/commit this nonsecret lock before rendering.
set -euo pipefail
cd -- "$(dirname -- "$0")/../.."
source scripts/helpers/check-target.sh
owned_namespace tableschnappi-demo
commit=$(jq -er '.buildCommit // .commit' config/source.lock.json)
tag=${commit:0:7}
output=config/images.params.new
awk '/^POSTGRES_IMAGE=/' config/images.params > "$output"
for pair in FRONTEND:frontend BACKEND:backend MCP:mcp ASSISTANT:mlflow-proxy WORKBENCH:workbench; do
  key=${pair%%:*}
  component=${pair#*:}
  image=$(oc get istag "tableschnappi-$component:$tag" -n tableschnappi-demo -o jsonpath='{.image.dockerImageReference}')
  [[ $image =~ @sha256:[a-f0-9]{64}$ ]]
  printf '%s_IMAGE=%s\n' "$key" "$image" >> "$output"
done
echo 'Inspect config/images.params.new, then replace config/images.params explicitly.'
