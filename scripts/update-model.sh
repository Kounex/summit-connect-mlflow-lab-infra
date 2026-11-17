#!/usr/bin/env bash
# Helm model/key update on existing stacks; preserve attendees' live guardrail policy.
set -euo pipefail
if [[ ${1:-} == --help ]]; then
  echo "Usage: $0 KEY [START END | --test | --users userN ...]"
  echo "       $0 --balanced QWEN_KEY GLM_KEY [START END | --test]"
  echo 'Keys: absolute private files. Requires Python with PyYAML.'
  echo 'Balanced: odd users Qwen, even users GLM, test Qwen; profiles in config/model-profiles/.'
  echo 'Single model: config/site-values.yaml, optionally overridden by MODEL_PROFILE.'
  echo 'MODEL_CONCURRENCY=1..8 (default 4). Restarts assistant, NeMo and workbench.'
  exit 0
fi
mode=single
if [[ ${1:-} == --balanced ]]; then mode=balanced; shift; fi
qwen_key=${1:?Supply an absolute private model-key file}; shift
glm_key=$qwen_key
if [[ $mode == balanced ]]; then glm_key=${1:?Supply GLM key file}; shift; fi
[[ $qwen_key == /* && -s $qwen_key && $glm_key == /* && -s $glm_key ]]
cd -- "$(dirname -- "$0")/.."
source scripts/helpers/participants.sh
if [[ ${1:-} == --users ]]; then
  shift
  [[ $# -gt 0 ]] || { echo 'Supply at least one participant after --users.' >&2; exit 1; }
  participants=("$@")
  seen=' '
  for participant in "${participants[@]}"; do
    participant_name "$participant"
    [[ $seen != *" $participant "* ]] || { echo "Duplicate participant: $participant" >&2; exit 1; }
    seen+="$participant "
  done
else
  participant_selection "$@"
fi
source scripts/helpers/check-target.sh
python3 -c 'import yaml'
# Helm 3 accepts an executable; Helm 4 uses a native postrenderer plugin.
export MODEL_POST_RENDERER="$PWD/scripts/helpers/model-renderer/render.py"
if [[ $(helm version --short) == v4.* ]]; then
  if ! helm plugin list | awk '{print $1}' | grep -qx lab-model-policy; then
    helm plugin install "$PWD/scripts/helpers/model-renderer" >&2
  fi
  MODEL_POST_RENDERER=lab-model-policy
fi
bash scripts/helpers/prepare-workbench-source.sh >&2
umask 077
export MODEL_BACKUP_DIR="${MODEL_BACKUP_DIR:-$HOME/.config/summit-connect-mlflow-lab/model-updates/$(date -u +%Y%m%d-%H%M%S)}"
python3 - "$mode" "$qwen_key" "$glm_key" "$MODEL_BACKUP_DIR" <<'PY'
import hashlib,json,os,sys,yaml
from pathlib import Path
mode,qwen_key,glm_key,directory=sys.argv[1:]
backup=Path(directory).resolve()
if backup.is_relative_to(Path.cwd().resolve()):raise SystemExit('Keep private backups outside the repository')
backup.mkdir(parents=True,exist_ok=True,mode=0o700);backup.chmod(0o700)
site=yaml.safe_load(Path('config/site-values.yaml').read_text())['model']
for name,key in [('qwen',qwen_key),('glm',glm_key)]:
 model=dict(site)
 profile=('config/model-profiles/'+name+'.yaml') if mode=='balanced' else os.environ.get('MODEL_PROFILE')
 if profile:model.update(yaml.safe_load(Path(profile).read_text())['model'])
 assert model['existingSecret']=='endpoint-api-key-1' and model['secretKey']=='api_key'
 assert model['endpoint'].startswith('https://') and model['name']
 Path('.cache/model-update-'+name+'.yaml').write_text(yaml.safe_dump({'model':model}))
 revision=hashlib.sha256(Path(key).read_bytes()+json.dumps(model,sort_keys=True).encode()).hexdigest()[:16]
 Path('.cache/model-update-'+name+'.revision').write_text(revision)
PY
update_one() {
  local participant=$1 profile=qwen key=$qwen_key
  if [[ $mode == balanced && $participant != test ]] && (( ${participant#user} % 2 == 0 )); then
    profile=glm; key=$glm_key
  fi
  bash scripts/helpers/update-participant-model.sh "$participant" "$key" ".cache/model-update-$profile.yaml" "$(cat ".cache/model-update-$profile.revision")"
}
# Apply every target first, then wait: slow workbench restarts must not delay
# changing the remaining restaurant assistants during a live event.
participant_batch "${MODEL_CONCURRENCY:-4}" update_one
wait_one() {
  local participant=$1 profile=qwen
  if [[ $mode == balanced && $participant != test ]] && (( ${participant#user} % 2 == 0 )); then profile=glm; fi
  bash scripts/helpers/wait-participant-model.sh "$participant" "$(cat ".cache/model-update-$profile.revision")"
}
participant_batch "${MODEL_CONCURRENCY:-4}" wait_one
printf 'Private rollback snapshots: %s\n' "$MODEL_BACKUP_DIR"
