#!/usr/bin/env bash
# Translate the nonsecret image digest lock into Helm values on stdout.
set -euo pipefail
cd -- "$(dirname -- "$0")/../.."
image() {
  local reference
  reference=$(awk -F= -v key="$1" '$1 == key { print substr($0, index($0,"=")+1) }' config/images.params)
  [[ $reference =~ @sha256:[a-f0-9]{64}$ ]] || { echo "Missing digest for $1" >&2; exit 1; }
  printf '%s' "$reference"
}
references=()
for key in FRONTEND_IMAGE BACKEND_IMAGE MCP_IMAGE ASSISTANT_IMAGE WORKBENCH_IMAGE; do
  reference=$(image "$key")
  references+=("$reference")
done
printf 'components:\n  frontend:\n    image: %s\n  backend:\n    image: %s\n  mcpServer:\n    image: %s\n  mlflowProxy:\n    image: %s\nworkbench:\n  image: %s\n' "${references[@]}"
