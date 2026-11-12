#!/usr/bin/env bash
# Only dynamic credentials cross this boundary; nonsecret infrastructure is YAML.
set -euo pipefail
if [[ ${1:-} == --help ]]; then
  echo "Usage: $0 database|mlflow (credential bootstrap; see README step 4)"; exit 0
fi
[[ $# == 1 && ( $1 == database || $1 == mlflow ) ]] || { echo "Usage: $0 database|mlflow" >&2; exit 1; }
cd -- "$(dirname -- "$0")/.."
source scripts/helpers/check-target.sh
owned_namespace tableschnappi-demo
owned_namespace redhat-ods-applications
phase=${1:?Usage: bootstrap-secrets.sh database|mlflow}
case $phase in
  database)
    if [[ -z $(oc get secret darmstadt-mlflow-db -n tableschnappi-demo --ignore-not-found -o name) ]]; then
      # A surviving PVC without its password needs recovery, not password regeneration.
      [[ -z $(oc get pvc darmstadt-postgresql -n tableschnappi-demo --ignore-not-found -o name) ]] || {
        echo 'Database PVC exists without its password Secret. Restore the Secret first.' >&2; exit 1;
      }
      oc process --local -f manifests/20-mlflow/database-secret.yaml -o yaml | oc create -f -
    fi
    [[ $(oc get secret darmstadt-mlflow-db -n tableschnappi-demo -o jsonpath='{.metadata.labels.event\.redhat\.com/owner}') == darmstadt-demo ]]
    ;;
  mlflow)
    umask 077
    scratch=$(mktemp -d)
    trap 'find "$scratch" -type f -exec unlink {} \;; rmdir "$scratch"' EXIT
    oc extract secret/darmstadt-mlflow-db -n tableschnappi-demo --keys=password --to="$scratch" >/dev/null
    password=$(cat "$scratch/password")
    # The database password generator uses hex, so URI encoding is unambiguous.
    [[ $password =~ ^[a-f0-9]{48}$ ]]
    printf '%s' "postgresql://mlflow:$password@darmstadt-postgresql.tableschnappi-demo.svc:5432/mlflow?sslmode=verify-full&sslrootcert=/etc/pki/tls/certs/combined/ca-bundle.crt" > "$scratch/backend-store-uri"
    oc extract secret/darmstadt-mlflow-artifacts -n tableschnappi-demo \
      --keys=AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY --to="$scratch" >/dev/null
    host=$(oc get cm darmstadt-mlflow-artifacts -n tableschnappi-demo -o jsonpath='{.data.BUCKET_HOST}')
    port=$(oc get cm darmstadt-mlflow-artifacts -n tableschnappi-demo -o jsonpath='{.data.BUCKET_PORT}')
    [[ -n $host && -n $port ]]
    printf '%s' "https://$host:$port" > "$scratch/MLFLOW_S3_ENDPOINT_URL"
    printf '%s' us-east-1 > "$scratch/AWS_DEFAULT_REGION"
    printf '%s' /etc/pki/tls/certs/combined/ca-bundle.crt > "$scratch/AWS_CA_BUNDLE"
    for secret_name in darmstadt-mlflow-db darmstadt-mlflow-s3; do
      if [[ -n $(oc get secret "$secret_name" -n redhat-ods-applications --ignore-not-found -o name) ]]; then
        [[ $(oc get secret "$secret_name" -n redhat-ods-applications -o jsonpath='{.metadata.labels.event\.redhat\.com/owner}') == darmstadt-demo ]]
      fi
    done
    oc create secret generic darmstadt-mlflow-db -n redhat-ods-applications --dry-run=client -o yaml \
      --from-file="backend-store-uri=$scratch/backend-store-uri" |
      oc label --local -f - event.redhat.com/owner=darmstadt-demo -o yaml |
      oc apply --server-side --field-manager=darmstadt-demo -f -
    oc create secret generic darmstadt-mlflow-s3 -n redhat-ods-applications --dry-run=client -o yaml \
      --from-file="$scratch/AWS_ACCESS_KEY_ID" --from-file="$scratch/AWS_SECRET_ACCESS_KEY" \
      --from-file="$scratch/MLFLOW_S3_ENDPOINT_URL" --from-file="$scratch/AWS_DEFAULT_REGION" --from-file="$scratch/AWS_CA_BUNDLE" |
      oc label --local -f - event.redhat.com/owner=darmstadt-demo -o yaml |
      oc apply --server-side --field-manager=darmstadt-demo -f -
    ;;
  *) echo 'Expected database or mlflow.' >&2; exit 1 ;;
esac
