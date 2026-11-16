#!/usr/bin/env bash
# Explicit workspace-history reset before participant recreation; backup first.
set -euo pipefail
if [[ ${1:-} == --help ]]; then
  echo "Usage: $0 --destroy-workspace-history userN|test /absolute/private-backup-directory"
  echo 'Exports metadata/artifacts, verifies the archive, then clears only that workspace.'
  exit 0
fi
[[ $# == 3 && $1 == --destroy-workspace-history && $3 == /* ]] || { echo 'Explicit history-reset flag, participant and private directory required.' >&2; exit 1; }
participant=$2
backup_dir=$3
cd -- "$(dirname -- "$0")/.."
source scripts/helpers/check-target.sh
participant_name "$participant"
owned_namespace "tableschnappi-$participant"
python3 - "$backup_dir" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]).resolve()
if p.is_relative_to(Path.cwd().resolve()):raise SystemExit('Keep backups outside the repository')
p.mkdir(parents=True,exist_ok=True,mode=0o700)
p.chmod(0o700)
PY
umask 077
archive="$backup_dir/$participant-mlflow-$(date +%Y%m%d-%H%M%S).tar.gz"
# Quiesce new restaurant trace writes while exporting/resetting this demo user.
oc scale deployment/tableschnappi-mlflow-proxy -n "tableschnappi-$participant" --replicas=0
oc rollout status deployment/tableschnappi-mlflow-proxy -n "tableschnappi-$participant" --timeout=120s
oc exec -i "$participant-0" -c "$participant" -n "tableschnappi-$participant" -- \
  python - export "tableschnappi-$participant" < scripts/helpers/mlflow-history.py > "$archive"
tar tzf "$archive" > /dev/null
inventory=$(python3 - "$archive" <<'PY'
import sys,tarfile
with tarfile.open(sys.argv[1]) as archive:print(archive.extractfile('inventory.json').read().decode())
PY
)
oc exec -i "$participant-0" -c "$participant" -n "tableschnappi-$participant" -- \
  python - clear "tableschnappi-$participant" "$inventory" < scripts/helpers/mlflow-history.py
printf 'Verified private workspace backup: %s\n' "$archive"
echo 'Now recreate this participant using delete-participants.sh and apply-participants.sh.'
