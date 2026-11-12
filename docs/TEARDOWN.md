# Reset and teardown

Use the dedicated kubeconfig and `EXPECTED_API_SERVER` from the runbook. Keep
OpenShift AI, TrustyAI, storage and MLflow controllers running until their CRs
and dependents have finished deleting. Never strip finalizers or delete
pre-existing storage/ingress/identity operators.

## One participant

Export participant notebooks and any restaurant state to retain first. This
deletes the entire participant project, including the 5 GiB notebook PVC and
model Secret. The backend's synthetic restaurant state is in memory. Shared
MLflow history is deliberately retained; recreating the same namespace restores
access to that workspace's retained experiments/prompts/traces.

```bash
bash scripts/delete-participants.sh --destroy-participant-data 50 50
```

The script checks target/name/ownership, removes NeMo and Notebook CRs while
their controllers are present, waits for namespace deletion, and deletes the
owned `restaurant-image-puller-user50` RoleBinding in `tableschnappi-demo`.
This binding lives outside the participant project and must not be left behind.
Recreate using `apply-participants.sh`, which applies native project scaffolding
and installs the pinned Helm release. New PVC content is initialized from the
source archive; the seed preserves existing MLflow prompt versions/aliases.

Validate that the old namespace UID and PVC/PV are gone, the generated NeMo and
workbench routes/resources are absent, and the external image-pull binding is
absent. Check the storage class/PV reclaim policy: namespace deletion alone is
not proof that a retained volume or its contents were removed.

## All participant projects

The following command is destructive and explicit. Run it only after exports:

```bash
DELETE_CONCURRENCY=8 bash scripts/delete-participants.sh --destroy-participant-data 1 50
oc get ns -l event.redhat.com/owner=darmstadt-demo
oc get rolebinding -n tableschnappi-demo -l event.redhat.com/owner=darmstadt-demo
```

## Participant accounts

Namespace cleanup does not delete accounts in the identity provider. For accounts
created by this runbook, **after** deleting their participant projects:

```bash
bash scripts/provision-accounts.sh --delete-owned-accounts \
  "$HOME/.config/restaurant-lab-accounts" 1 1
```

Use the same private receipt directory and explicit range as provisioning. The
helper checks the issuer, exact username and recorded Keycloak user ID, deletes
only those accounts, revokes their OpenShift OAuth access/authorization tokens,
and removes their corresponding OpenShift User/Identity records. It retains the
private receipt for audit; a later create generates a new ID and reuses the `userN:userN` demo convention. Do not
delete the existing realm, clients, admin account, Keycloak CR or operator.
Accounts provided by another identity system need that system's cleanup process.

Deletion defaults to one participant at a time. `DELETE_CONCURRENCY=1..8`
allows independent namespaces to clean up concurrently; each retains the same
name/ownership guards and waits. A failed group stops later groups.

## Shared lab data

Back up the database, its original password Secret and S3 artifacts together,
then verify a restore before deleting them if event history must be retained.
Mirror the app image digests if identical redeployment is required. Database
and object storage backups contain participant data; keep them private.

Stop if any participant projects remain or if the resources are not lab-owned.
Only delete the MLflow singleton if this installation was created for this lab.

```bash
set -euo pipefail
: "${KUBECONFIG:?Set the dedicated kubeconfig}"
: "${EXPECTED_API_SERVER:?Set the intended API URL}"
[[ $(oc whoami --show-server) == "$EXPECTED_API_SERVER" ]]
[[ $(oc get ns tableschnappi-demo -o jsonpath='{.metadata.labels.event\.redhat\.com/owner}') == darmstadt-demo ]]
[[ $(oc get mlflow mlflow -o jsonpath='{.metadata.labels.event\.redhat\.com/owner}') == darmstadt-demo ]]
remaining=$(oc get ns -l event.redhat.com/owner=darmstadt-demo -o json | jq '[.items[] | select(.metadata.name | startswith("tableschnappi-user"))] | length')
[[ $remaining == 0 ]]
oc delete mlflow mlflow --wait=true --timeout=300s
for secret in darmstadt-mlflow-db darmstadt-mlflow-s3; do
  [[ $(oc get secret "$secret" -n redhat-ods-applications -o jsonpath='{.metadata.labels.event\.redhat\.com/owner}') == darmstadt-demo ]]
  oc delete secret "$secret" -n redhat-ods-applications
done
oc delete obc darmstadt-mlflow-artifacts -n tableschnappi-demo --wait=true --timeout=300s
# Confirm the ODF ObjectBucket and bucket were removed per the provisioner's policy.
oc get objectbucket
oc delete namespace tableschnappi-demo --wait=true --timeout=600s
```

This removes PostgreSQL/PVC, the model-key source if stored there, builds and
image streams. Inspect retained PVs and the actual ODF bucket lifecycle; if a
Retain policy applies, remove only the recorded lab volume/bucket through the
storage administrator's normal procedure. Do not delete all PVs/ObjectBuckets.
Keep the service-CA/certificate controllers alive during storage removal.

## Model catalog and registry namespace

The model catalog is enabled through the DSC's managed `modelregistry`
component. Before uninstalling AI, inspect its namespace:

```bash
oc get modelregistries.modelregistry.opendatahub.io -n rhoai-model-registries
oc get deployments,pvc -n rhoai-model-registries
```

The catalog PostgreSQL cache uses `emptyDir`; catalog sources repopulate it.
The separate `ModelRegistry/summit-connect` owns a PostgreSQL deployment,
credential Secrets and a 5 GiB PVC. Export any registry metadata to retain before
deleting that CR: its PVC is garbage-collected too. Keep the registry operator
running until its finalizer has completed. Do not delete MLflow storage for this
registry cleanup; they are separate databases.

Remove only the lab-owned registry while the operator is available:

```bash
[[ $(oc get modelregistries.modelregistry.opendatahub.io summit-connect -n rhoai-model-registries -o jsonpath='{.metadata.labels.event\.redhat\.com/owner}') == darmstadt-demo ]]
oc delete -f manifests/00-platform/model-registry-access.yaml --ignore-not-found
oc delete -f manifests/00-platform/model-registry.yaml --wait=true --timeout=300s
oc wait --for=delete deployment/summit-connect deployment/summit-connect-postgres pvc/summit-connect-postgres-storage -n rhoai-model-registries --timeout=300s
```

Check the recorded registry PV's reclaim policy and removal. The tested default
RBD volume used `Delete`; do not assume that on another storage class. RHOAI
3.5.2 removes the generated OpenShift Group `summit-connect-users` and its
cross-namespace HTTPRoute, but leaves `ClusterRoleBinding/summit-connect-auth-delegator`.
Its namespace-less resource cannot be owned by the namespaced CR. Remove that
specific leftover using the installation receipt, labels and service-account
subject, never a broad RBAC name match:

```bash
if [[ -n $(oc get clusterrolebinding summit-connect-auth-delegator --ignore-not-found -o name) ]]; then
  expected_uid=$(jq -er .metadata.uid rendered/model-registry/auth-delegator.json)
  oc get clusterrolebinding summit-connect-auth-delegator -o json | jq -e --arg uid "$expected_uid" '
    .metadata.uid == $uid and
    .metadata.labels.app == "summit-connect" and
    .metadata.labels["modelregistry.opendatahub.io/namespace"] == "rhoai-model-registries" and
    .roleRef.name == "system:auth-delegator" and
    .subjects == [{"kind":"ServiceAccount","name":"summit-connect","namespace":"rhoai-model-registries"}]'
  oc delete clusterrolebinding summit-connect-auth-delegator
fi
oc get group summit-connect-users --ignore-not-found -o name
```

If the receipt is missing or an assertion fails, inspect provenance rather than
bypassing the checks. No finalizer edits are needed. This registry/PVC/PV cleanup
and recreation was exercised before publishing the access policy. Other registry
instances or data need their own deliberate export/cleanup.

Remove the lab-owned access binding during full teardown:

```bash
oc delete -f manifests/00-platform/model-catalog-access.yaml --ignore-not-found
```

The operator's separate default binding remains while the catalog is installed;
this is cleanup of our policy resource, not an access-revocation procedure.

After the normal native AI uninstall, check whether `rhoai-model-registries`
remains. Remove that namespace only when the saved baseline confirms this lab
created it, its `platform.opendatahub.io/part-of: modelregistry` provenance matches,
and no other registry instances/data need retaining. The enablement step saves
its UID in ignored `rendered/model-catalog-namespace.json`. Check that UID as
with other residual namespaces; do not add it to a blind namespace deletion list.
The dashboard catalog flag disappears with the AI dashboard resources.

## Lab-owned OpenShift AI installation

Skip this section completely when RHOAI was already present before the lab.
Compare the saved baseline, Subscription CSV and actual resources first. This
is cluster-wide cleanup, not participant reset. The documented RHOAI uninstaller
uses the checked-in ConfigMap and the still-running AI operator.

```bash
set -euo pipefail
: "${KUBECONFIG:?Set the dedicated kubeconfig}"
: "${EXPECTED_API_SERVER:?Set the intended API URL}"
[[ $(oc whoami --show-server) == "$EXPECTED_API_SERVER" ]]
[[ $(oc get ns redhat-ods-operator -o jsonpath='{.metadata.labels.event\.redhat\.com/owner}') == darmstadt-demo ]]
[[ $(oc get subscription rhods-operator -n redhat-ods-operator -o jsonpath='{.spec.channel}') == stable-3.5 ]]
oc apply --server-side --field-manager=darmstadt-demo -f manifests/90-operations/uninstall-ai.yaml
# Observe progress; allow controllers to reconcile:
oc get dsc,dscinitialization
for namespace in redhat-ods-applications redhat-ods-monitoring rhods-notebooks; do
  if [[ -n $(oc get namespace "$namespace" --ignore-not-found -o name) ]]; then
    oc wait --for=delete "namespace/$namespace" --timeout=1800s
  fi
done
# These waits must succeed before removing the operator:
oc delete namespace redhat-ods-operator --wait=true --timeout=600s
```

If cleanup stalls, inspect the operator logs, remaining CRs and finalizers;
resolve the underlying error. Deleting the operator before reconciliation
completes leaves resources behind.

RHOAI 3.5.2 left 20 default LLM configuration resources after deleting their
controller during the migration rehearsal. The native controller was restored
temporarily and finalized them normally. The exact manifests, conditions and
cleanup commands are in the [LLM controller recovery guide](../manifests/90-operations/recovery/README.md).
Use it only for that observed failure; finalizers are not manually stripped.
The uninstaller also left an empty lab-created `opendatahub-ogx-system`
namespace. Verify its recorded UID, creation/provenance and absence of workloads
before deleting that namespace. Do not infer ownership from a name alone.

Compare remaining namespaces, CRDs, ClusterRoles and ClusterRoleBindings with
`rendered/baseline/`. Operator uninstall can leave CRDs/RBAC. Inventory all CR
instances before considering deletion of a newly introduced CRD. Remove a
cluster-scoped resource only when its baseline absence, lab ownership/provenance
and lack of other consumers are established. Never use a broad `odh`, `istio`
or `mlflow` name match as deletion authority. Preserve existing Gateway/Istio,
cert-manager, ODF, Keycloak, GitOps and External Secrets resources.

The lab no longer enables AI asset discovery UI features. For any earlier
site-specific dashboard edits, restore saved values rather than guessed defaults.

## Residual cleanup after native uninstall

The native uninstaller can leave resources behind. Compare its result with
`rendered/baseline/`. Remove a residual resource only when its baseline absence,
AI provenance and lack of other consumers are established. Inventory instances
before deleting a CRD. Do not use a name prefix as deletion authority.

Check for orphaned AI Auth resources, empty AI-installed CRDs/RBAC, AI OAuth
clients/tokens, injected CA ConfigMaps and unused AI gateway resources. Preserve
shared ingress, service CA, identity, storage and GitOps resources. Check workload
references before removing ConfigMaps, Secrets or service accounts. The recorded
baseline and actual references determine ownership, not a generic deletion list.

Registry image references disappear with the lab namespace. Physical blob
reclamation follows the shared registry's normal pruning policy. Verify retained
PVs and ObjectBuckets separately.

Participant and complete AI teardown have been rehearsed, including the specific
3.5.2 recovery above. Model catalog enablement was added afterwards; its complete
teardown has not yet been rehearsed. See [validation limits](VALIDATION.md).
