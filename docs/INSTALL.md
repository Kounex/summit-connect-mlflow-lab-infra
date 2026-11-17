# Installation runbook

Run these steps **from the repository root, in order**. Start with one participant
(`1 1`), rehearse the lab, then expand. Platform configuration uses checked-in
YAML and server-side apply; the pinned application Helm chart owns restaurant
and workbench resources. Do not apply `manifests/` recursively.

[Repository overview](../README.md) · [Architecture](DEMO.md) · [Teardown](TEARDOWN.md)

## 1. Configure the target

You need Bash, Python 3.9+, Git, jq, Helm 3 and an `oc` client matching OpenShift 4.22, and cluster-admin
access. The cluster must already have:

- Working ingress/OAuth and image pull entitlement for RHOAI/registry.redhat.io.
- A managed integrated image registry and default dynamic RBD storage class.
- ODF/NooBaa storage class `openshift-storage.noobaa.io` and working cert-manager.
- Participant identities authenticating as `user1`–`user50`, plus internal `test`, before the event
  (or use the optional existing-Keycloak command below).

The installation starts with **no OpenShift AI components or restaurant lab installed**.
An operator-only bootstrap can be reused as described in step 2.
It installs AI and the lab, not OpenShift itself, ODF or the identity provider.
Do not adopt an unrelated existing AI installation or project using these manifests.

```bash
set -euo pipefail
export KUBECONFIG="$HOME/.config/restaurant-lab.kubeconfig"
export EXPECTED_API_SERVER=https://api.YOUR_CLUSTER:6443
oc login --server="$EXPECTED_API_SERVER"
[[ $(oc whoami --show-server) == "$EXPECTED_API_SERVER" ]] || { echo 'Cluster mismatch'; exit 1; }
mkdir -p rendered/baseline
oc get ns -o json > rendered/baseline/namespaces.json
oc get subscriptions -A -o json > rendered/baseline/subscriptions.json
oc get crd -o json > rendered/baseline/crds.json
oc get clusterrole,clusterrolebinding -o json > rendered/baseline/rbac.json
oc get nodes -o json > rendered/baseline/nodes.json
cp config/site-values.example.yaml config/site-values.yaml
oc get ingresses.config/cluster -o jsonpath='{.spec.domain}{"\n"}'
```

Edit **`config/site-values.yaml`**: set `rhoai.appsDomain`, the shared MLflow
tracking/UI URLs, `model.endpoint` (origin without `/v1`) and `model.name`.
Keep `model.existingSecret: endpoint-api-key-1` and `model.secretKey: api_key`.
Store the API key in a private nonempty file outside Git. The key is supplied
by filename and never appears in Helm values or preview output. Do not use `set -x`.

This profile uses Qwen with thinking disabled. Other models need tool-calling
and request-option checks. Current source retains workshop TLS/fail-open
behavior; see [demo limitations](DEMO.md#limitations).

## 2. Install OpenShift AI — once

```bash
oc apply --server-side --field-manager=darmstadt-demo -f manifests/00-platform/namespaces.yaml
# A cluster can already have a bootstrap RHOAI operator/OperatorGroup.
# Inspect first; do not add a second OperatorGroup in that namespace.
oc get operatorgroup,subscription,csv -n redhat-ods-operator
if [[ -z $(oc get operatorgroup -n redhat-ods-operator -o name) ]]; then
  oc apply --server-side --field-manager=darmstadt-demo -f manifests/00-platform/operator-group.yaml
fi
oc apply --server-side --field-manager=darmstadt-demo -f manifests/00-platform/subscription.yaml
# OLM installs and approves the stable-channel operator automatically.
deadline=$((SECONDS + 900))
installed_csv=""
while [[ -z "$installed_csv" ]]; do
  installed_csv=$(oc get subscription rhods-operator -n redhat-ods-operator -o jsonpath='{.status.installedCSV}')
  [[ $SECONDS -lt $deadline ]] || { echo 'Operator installation did not complete'; exit 1; }
  [[ -n "$installed_csv" ]] || sleep 2
done
oc wait "csv/$installed_csv" -n redhat-ods-operator --for=jsonpath='{.status.phase}'=Succeeded --timeout=900s
oc apply --server-side --field-manager=darmstadt-demo -f manifests/00-platform/datasciencecluster.yaml
# Wait for the newly enabled component even when this DSC was already Ready.
oc wait dsc/default-dsc --for=condition=ModelRegistryReady --timeout=900s
oc wait dsc/default-dsc --for=condition=Ready --timeout=900s
oc apply --server-side --field-manager=darmstadt-demo -f manifests/00-platform/model-catalog.yaml
oc rollout status deployment/model-registry-operator-controller-manager -n redhat-ods-applications --timeout=600s
oc rollout status deployment/model-registry-ui -n redhat-ods-applications --timeout=600s
oc rollout status deployment/model-catalog -n rhoai-model-registries --timeout=600s
oc rollout status deployment/model-catalog-postgres -n rhoai-model-registries --timeout=600s
oc apply --server-side --field-manager=darmstadt-demo -f manifests/00-platform/model-catalog-access.yaml
oc get namespace rhoai-model-registries -o json > rendered/model-catalog-namespace.json
# Separate user model registry; the catalog above is only for discovery.
oc apply --server-side --field-manager=darmstadt-demo -f manifests/00-platform/model-registry.yaml
oc wait modelregistries.modelregistry.opendatahub.io/summit-connect -n rhoai-model-registries --for=condition=Available --timeout=600s
oc get role registry-user-summit-connect -n rhoai-model-registries -o name
oc apply --server-side --field-manager=darmstadt-demo -f manifests/00-platform/model-registry-access.yaml
mkdir -p rendered/model-registry
oc get clusterrolebinding summit-connect-auth-delegator -o json > rendered/model-registry/auth-delegator.json
```

A preinstalled bootstrap operator with no `DataScienceCluster` or AI user
workloads can be reused. Keep its existing OperatorGroup. If the Subscription
channel belongs to the bootstrap/browser field manager, inspect the exact diff
before transferring that ownership:

```bash
oc diff --server-side --field-manager=darmstadt-demo --force-conflicts \
  -f manifests/00-platform/subscription.yaml
# Only after verifying the intended channel/ownership changes:
oc apply --server-side --field-manager=darmstadt-demo --force-conflicts \
  -f manifests/00-platform/subscription.yaml
```

This exception is scoped to that reviewed Subscription. It is not a general
instruction to force other conflicts or adopt an unrelated AI installation.
Preserve the before-install inventory for later ownership decisions. Automatic
approval does not require editing an InstallPlan.

The Subscription follows `stable-3.5` with `installPlanApproval: Automatic`.
There is no manual InstallPlan patch or exact-CSV acceptance check. Channel
updates are accepted as the demo policy. The tested CSV in the source metadata
is informational; changing the minor channel is a deliberate configuration edit.
The DSC enables dashboard, workbenches, pipelines, KServe, TrustyAI, MLflow
operator, model registry/catalog and OGX. Waits are needed because
CRDs/controllers become ready asynchronously.

The catalog backend comes from `spec.components.modelregistry.managementState:
Managed`, with native registry namespace `rhoai-model-registries`. The separate
`model-catalog.yaml` makes `disableModelCatalog: false` explicit in the dashboard
configuration. Open **AI hub → Models → Catalog** to browse the configured sources.
The operator creates the catalog server and its PostgreSQL cache in
`rhoai-model-registries`; this version uses `emptyDir` for that cache, with no
PVC. The separate `ModelRegistry/summit-connect` below owns its own database
and persistent volume. Reload an already-open dashboard after enabling the component.

`model-catalog-access.yaml` explicitly binds the operator's namespace-local
`Role/model-catalog` to `system:authenticated`. Every normal authenticated user
can browse the catalog, including future participant accounts; there is no
per-user list or catalog-admin grant. The role grants `get` on only the catalog
Service and Endpoints, as required by its authentication proxy. The operator
also creates an equivalent default binding; this separate lab-owned binding
records our policy without modifying operator-owned resources.

Verify a normal user's authorization (this check does not create the account):

```bash
oc auth can-i get services/model-catalog -n rhoai-model-registries \
  --as=user50 --as-group=system:authenticated
# Expected: yes
oc auth can-i get secrets -n rhoai-model-registries \
  --as=user50 --as-group=system:authenticated
# Expected: no
```

References: [enable the registry/catalog component](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/managing_model_registries/enabling-the-model-registry-component_managing-model-registries),
[dashboard catalog setting](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/managing_resources/customizing-the-dashboard).

### Shared model registry

`model-registry.yaml` declares `ModelRegistry/summit-connect` in
`rhoai-model-registries`. `postgres.generateDeployment: true` selects the native
nonproduction database: the registry operator creates PostgreSQL, generated
credential Secrets and a 5 GiB PVC using the default storage class. No database
password or extra bootstrap script is needed. This is the product's demo database,
not an HA database service. Deleting the registry also deletes its owned PVC.

Open **AI hub → Models → Registry**. It is separate from **Catalog**, which lists
provided model sources, and from MLflow, which stores workshop traces/prompts.
The restaurant and notebook continue using their configured external model API;
creating this registry does not import, proxy or deploy that endpoint.

`model-registry-access.yaml` binds the operator-created
`Role/registry-user-summit-connect` to `system:authenticated`. All authenticated
users can use the shared registry, including registering/editing model metadata.
Records here are shared; this is not a per-participant registry. MLflow workspace
permissions remain namespace based. The role allows `get` on the named registry
Service/Endpoints for its authentication proxy; it does not grant database Secret
access or registry administration. The singular role spelling above is verified
on RHOAI 3.5.2; inspect the generated role when upgrading the operator.

```bash
oc auth can-i get services/summit-connect -n rhoai-model-registries \
  --as=user50 --as-group=system:authenticated
# Expected: yes; this does not create a user50 account.
oc auth can-i get secrets -n rhoai-model-registries \
  --as=user50 --as-group=system:authenticated
# Expected: no.
```

Use the fully qualified `modelregistries.modelregistry.opendatahub.io` name in
commands: this cluster also has a platform component resource called ModelRegistry.
The saved auth-binding receipt supports the scoped cleanup in
[teardown](TEARDOWN.md#model-catalog-and-registry-namespace).
References: [native registry database](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/managing_model_registries/creating-a-model-registry_managing-model-registries),
[registry access](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/managing_model_registries/managing-model-registry-permissions_managing-model-registries).

## 3. Build the application and prepared workbench — once

```bash
bash scripts/build-images.sh
# Inspect the five resolved app/workbench digests, then keep the new lock:
mv config/images.params.new config/images.params
```

The five BuildConfigs fetch the public application repository at an explicit commit. Dockerfile
paths and build contexts are in their YAML; no local archive upload is needed.
Keep those refs aligned with `buildCommit` in `config/source.lock.json`;
`commit` independently pins the chart and workbench source. The image lock records the
original site's images; building and refreshing it is required at a new site.
The application repository also publishes service images to GHCR, but this
runbook builds all five lab images in OpenShift and uses their integrated-registry
digests. It does not automatically consume GHCR images. The workbench image is
not currently published by that GitHub workflow; its Red Hat base is pulled using
the cluster's existing registry entitlement.

The workbench BuildConfig adds the pinned lab dependencies to a digest-pinned
RHOAI base; PostgreSQL is also digest-pinned. Commit the updated
nonsecret lock for your site. Rebuilding source can change bytes if upstream
packages/base images change; mirror existing digests for identical image replay.

## 4. Install shared storage and MLflow — once

```bash
bash scripts/bootstrap-secrets.sh database
oc process --local -f manifests/20-mlflow/storage.yaml \
  --param-file=config/images.params --ignore-unknown-parameters -o yaml > rendered/storage.yaml
# Inspect rendered/storage.yaml before applying.
oc apply --server-side --field-manager=darmstadt-demo -f rendered/storage.yaml
oc wait obc/darmstadt-mlflow-artifacts -n tableschnappi-demo --for=jsonpath='{.status.phase}'=Bound --timeout=300s
oc rollout status deployment/darmstadt-postgresql -n tableschnappi-demo --timeout=300s
bash scripts/bootstrap-secrets.sh mlflow
bucket=$(oc get cm darmstadt-mlflow-artifacts -n tableschnappi-demo -o jsonpath='{.data.BUCKET_NAME}')
[[ -n "$bucket" ]]
oc process --local -f manifests/20-mlflow/mlflow.yaml -p "BUCKET_NAME=$bucket" -o yaml > rendered/mlflow.yaml
# Inspect rendered/mlflow.yaml before applying.
oc apply --server-side --field-manager=darmstadt-demo -f rendered/mlflow.yaml
oc wait mlflow/mlflow --for=condition=Available --timeout=900s
```

The database password is created once and reused. Never recreate it while
keeping its PVC. ODF generates bucket credentials; the Secret helper copies
them and the database URI into MLflow's namespace. Storage uses service-CA TLS.
PostgreSQL is a single lab Deployment, not an operator-managed HA database.

## 5. Install participants with Helm

Native project YAML defines the Namespace, quota, limits, ingress policy and
cross-project registry pull grant. Helm owns the workbench/PVC, human/service
account RoleBindings, restaurant services, NeMo and prompt seed. There
is one application definition: the application's chart, not a second set of local app YAMLs.

The entry script packages the pinned source once, applies project/Secret/source
ConfigMap resources with SSA, then runs `helm upgrade --install --wait` using the
same pinned chart, site values and digest lock. It waits for the workbench and
NeMo controller workloads. There are no per-user generated manifest directories.
A Helm image-values file is generated once in `.cache/` from `config/images.params`.

For the first pilot:

```bash
bash scripts/validate.sh 1 1
bash scripts/render-participants.sh 1 1 > /tmp/user1-preview.yaml
# Read the project resources and chart output. Then install:
bash scripts/apply-participants.sh /private/path/model-api-key 1 1
bash scripts/warm-guardrails.sh 1 1
```

The preview includes Helm hook Jobs. It is for review; applying the full preview
with `oc` does not reproduce Helm's hook ordering and readiness waits.
The explicit manual equivalent of the application step is:

```bash
helm upgrade --install tableschnappi .cache/chart-$(jq -r .commit config/source.lock.json) \
  -n tableschnappi-user1 \
  -f .cache/chart-$(jq -r .commit config/source.lock.json)/values-multi-user.yaml \
  -f config/site-values.yaml -f .cache/image-values.yaml \
  --set workbench.name=user1 --set workbench.username=user1 \
  --set workbench.sourceConfigMap=workshop-source \
  --set-string workbench.repoRef=$(jq -r .commit config/source.lock.json) \
  --wait --timeout 15m
```

Namespace, grants, Secret and source ConfigMap must exist first; the entry script
handles those prerequisites. Never adopt the old plain-YAML workloads implicitly.
For this disposable demo, migrate an existing participant using the documented
reset, then reinstall. This deletes their notebook PVC and synthetic restaurant
state while retaining shared MLflow history:

```bash
bash scripts/delete-participants.sh --destroy-participant-data 1 1
bash scripts/apply-participants.sh /private/path/model-api-key 1 1
bash scripts/warm-guardrails.sh 1 1
```

After the pilot, apply the full roster or an explicit range:

```bash
APPLY_CONCURRENCY=4 bash scripts/apply-participants.sh /private/path/model-api-key 1 50
WARM_CONCURRENCY=4 bash scripts/warm-guardrails.sh 1 50
# Identical, separate internal troubleshooting stack:
bash scripts/apply-participants.sh /private/path/model-api-key --test
bash scripts/warm-guardrails.sh --test
```

No range means users 1 through `participantCount` (50). Supplying `7 7` targets
only user7. `--test` selects only `tableschnappi-test`; numeric batches never
include it. Apply defaults to sequential; `APPLY_CONCURRENCY=1..8` enables
bounded groups after checking capacity. A failed group is fully awaited and
stops later groups; successful participants remain available. The batch is not
a transaction. Use one apply entry at a time: source packaging/cache preparation
is shared. `WARM_CONCURRENCY=1..8` controls independent guardrail warmup Jobs.

For an existing Helm participant, `apply-participants.sh --dry-run KEY START END`
uses SSA server dry-run for project/config resources and Helm server dry-run for
the chart. It does not perform installation hooks or waits. New namespaces cannot
be created for dependent API requests by a dry-run; preview them locally instead.

Participant identities must authenticate as `user1`–`user50`; project names and
RoleBindings do not create Keycloak accounts. The prepared workbench image has
the required notebook packages. Native MLflow connection/auth comes from the
Notebook annotation; attendees do not install packages or paste model keys.

### Optional: existing Keycloak participant accounts

Project/User/RoleBinding YAML does not create a password in an external identity
provider. Use this option only when OpenShift already authenticates against
Keycloak. Keep its realm, clients and admin account intact. To provision a pilot
through the same range mechanism used for the roster:

**Demo login convention: username and password are identical**, from
`user1:user1` through `user50:user50`, plus **`test:test`**. Passwords are permanent; attendees do not
have to change them at first login.

```bash
bash scripts/provision-accounts.sh "$HOME/.config/restaurant-lab-accounts" 1 1
# After pilot acceptance, provision the full roster and internal account:
bash scripts/provision-accounts.sh "$HOME/.config/restaurant-lab-accounts" 1 50
bash scripts/provision-accounts.sh "$HOME/.config/restaurant-lab-accounts" --test
```

This optional entry uses the Keycloak Admin REST API with the existing bootstrap
admin Secret; it does not install an identity provider. The defaults are OpenShift
IDP `rhbk`, namespace `keycloak`, Secret `keycloak-initial-admin` (keys `username`
and `password`). Override with `KEYCLOAK_IDP`, `KEYCLOAK_NAMESPACE` and
`KEYCLOAK_ADMIN_SECRET` when your site differs. HTTPS verification remains enabled;
if your Python installation lacks system roots, configure `SSL_CERT_FILE` to its
trusted CA bundle.

The account definition is `manifests/40-accounts/user.json`, the native Keycloak
REST representation. Its credential value uses the same `${PARTICIPANT}`
placeholder as the username; the helper adds the generated account ID. Ownership
receipts, including the demo password, stay in the private directory (mode 700;
files 600). Reruns reset recorded accounts to the declared matching password;
unrecorded existing accounts are rejected. The OpenShift User/Identity records
appear at first SSO login. For cleanup, keep the private receipts and follow
[account teardown](TEARDOWN.md#participant-accounts).

Keycloak's [realm-import resource](https://www.keycloak.org/operator/realm-import)
creates new realms only; it cannot update users in an existing realm. This is
why accounts use its [Admin REST API](https://www.keycloak.org/docs-api/latest/rest-api/)
rather than another `oc apply`. On a different identity provider, provision the
same participant names through that provider instead; skip this optional step.

## 6. Verify readiness and hand over to the workshop

Use the application repository's
[instructor preparation](https://github.com/Kounex/tableschnappi/blob/main/docs/INSTRUCTOR.md)
and [attendee workshop](https://github.com/Kounex/tableschnappi/blob/main/workshop/README.md)
for the rehearsal, schedule and exercises. Run the baseline checks first:

```bash
bash scripts/check-readiness.sh 1 50
bash scripts/check-readiness.sh --test
```

These checks use each workbench's native identity and verify rollouts, source,
model-key presence, prompt aliases at version 1, empty guardrails, MCP discovery
and notebook dependencies. Attendees must also have no active runs/traces; `test`
can retain troubleshooting history. The checks make no model calls or trace writes. These are
pre-event baseline checks; attendee edits during the lab can intentionally make
them fail. `CHECK_CONCURRENCY=1..8` controls parallelism (default 4).
Rehearse model calls, prompt changes and guardrails with `test:test` to keep
attendee workspaces clean. The test user has the same namespace-local rights,
quotas and stack, with no extra privileges. This infrastructure repository does
not duplicate those steps. Prepare each attendee's restaurant, MLflow, OpenShift
AI and Console links. Verify project access and workbench readiness before the event.

The chart starts NeMo with `rails.input.flows: []` and keeps assistant shields
connected. Warm the empty-policy baseline after deployment using
`scripts/warm-guardrails.sh START END`. During instructor checks after a blocking
policy is enabled, `--expect-blocked` checks the allowed/blocked pair. After
restoring the empty policy/restarting NeMo, warm without that flag. The application
instructor guide owns policy/reset instructions and the attendee ConfigMap edits.

For participant deletion or full environment removal, use [TEARDOWN.md](TEARDOWN.md).
Check [validation coverage and remaining gates](VALIDATION.md) before scaling up.

## Change models on existing stacks

Keep keys in separate private files outside Git. The checked-in
`config/model-profiles/qwen.yaml` and `glm.yaml` describe the nonsecret model
settings. Review/edit those endpoints and names for your provider. For the event,
use **odd users → Qwen, even users → GLM** (25 each); `test` uses Qwen:

```bash
# Run from the repo root with the target kubeconfig/API guard already set.
# Requires Python with PyYAML; uv supplies an isolated environment here.
MODEL_CONCURRENCY=8 uv run --with pyyaml bash scripts/update-model.sh --balanced \
  /private/path/qwen-api-key /private/path/glm-api-key 1 50
uv run --with pyyaml bash scripts/update-model.sh --balanced \
  /private/path/qwen-api-key /private/path/glm-api-key --test
```

This upgrades existing Helm releases with their current values plus the selected
model profile. It applies each namespace's model Secret with SSA, preserves the
live NeMo policy and custom flow files, and changes only its model configuration.
A credential revision restarts the assistant, NeMo and notebook even for key-only
rotation. Workbench kernels restart; saved files/PVCs, MLflow history and prompt
aliases are retained. Helm hooks are skipped because this operation needs no
prompt seeding, image build or source reset. Readiness waits and a NeMo restaurant
request complete each participant update. Groups stop on failure.

Do not run another model/apply/render entry concurrently: source/profile caches
are shared. Do not edit running scripts. The normal `apply-participants.sh`
installation uses the common site configuration; **rerun this model assignment
after any normal reapply**, and use this update command during the workshop to
retain attendee guardrail edits. A new-cluster replay installs the common stack
first, then applies this assignment before handover.

Helm 3 uses the executable renderer directly. Helm 4 installs the repository's
small [native postrenderer plugin](../scripts/helpers/model-renderer/plugin.yaml)
and uses client-side three-way updates for this operation, retaining live edits
without forcing SSA ownership conflicts. The Secret boundary still uses SSA.
See [Helm's postrenderer plugin workflow](https://helm.sh/docs/plugins/developer/tutorial-postrenderer-plugin/).
The entry command requires PyYAML only for parsing/merging model and policy YAML;
existing installation commands do not acquire that dependency.

For a single profile/range, `MODEL_PROFILE=config/model-profiles/glm.yaml` with
`update-model.sh /private/path/glm-api-key 2 2` overrides the common site's model
settings. Omitting `MODEL_PROFILE` uses `config/site-values.yaml`. Keep the same
profile/key pairing when reapplying a range. Private before-change values, policy
and Secret snapshots are saved under
`$HOME/.config/summit-connect-mlflow-lab/model-updates/`; `MODEL_BACKUP_DIR` can
select another directory outside Git. To roll back a participant, supply its
previous key and model profile to the same command. Never paste Secret exports
into the public repository.

## What belongs in YAML, and what still needs an operation?

Subscriptions/OperatorGroups, the DSC, projects, permissions,
quotas, policies, storage and workloads are all in `manifests/`. Helpers do not
define an alternative desired state. Use SSA for persistent configuration:

```bash
oc diff --server-side --field-manager=darmstadt-demo -f rendered/storage.yaml || [[ $? == 1 ]]
oc apply --server-side --field-manager=darmstadt-demo -f rendered/storage.yaml
```

Diff exit 1 means changes; other failures must be resolved. Keep each resource's
owned configuration together, omit operator-managed/default/status fields, and
inspect conflicts. Do not use `--force-conflicts` by default. Omitting a field
previously owned by this manager can remove/reset it; the same manager also does
not protect participant edits against its own later reapply. For existing
resources owned by other tools, review the ownership transition before migration.

## Entry scripts and internal helpers

| Entry command | Purpose |
|---|---|
| `scripts/build-images.sh` | Apply five Git BuildConfigs, start builds, wait and resolve image digests |
| `scripts/bootstrap-secrets.sh database` / `mlflow` | Initial database password / generated storage credentials |
| `scripts/render-participants.sh [START END or --test]` | Review project/source/chart YAML on stdout |
| `scripts/apply-participants.sh [--dry-run] /absolute/key-file [START END or --test]` | Native project resources plus pinned Helm installation |
| `scripts/validate.sh [START END or --test]` | Local project/chart rendering checks |
| `scripts/warm-guardrails.sh [--expect-blocked] START END or --test` | Warm/check baseline or enabled NeMo policy |
| `scripts/update-model.sh [--balanced] KEY(S) [START END or --test]` | Switch model/credentials on existing stacks, preserving live guardrail policy |
| `scripts/check-readiness.sh [START END or --test]` | Read-only rollout, native MLflow, baseline and notebook/MCP checks |
| `scripts/reset-mlflow.sh --destroy-workspace-history userN-or-test /absolute/private-backup-directory` | Export/verify and clear one workspace before project recreation |
| `scripts/provision-accounts.sh /absolute/private-directory START END or --test` | Create selected existing-Keycloak accounts; `--delete-owned-accounts` cleans them up |
| `scripts/delete-participants.sh --destroy-participant-data START END or --test` | Explicit namespace/PVC and external pull-grant cleanup |

Every entry supports `--help`. `scripts/helpers/` implements one-participant
operations, source/chart packaging and image-value generation; normally run the
entry commands. Operators reconcile their managed components. SSA and Helm
installation alone do not create continuous GitOps reconciliation.

References: [SSA field ownership](https://kubernetes.io/docs/reference/using-api/server-side-apply/),
[OpenShift Git build inputs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/observability/builds_using_buildconfig/creating-build-inputs),
[custom RHOAI workbench images](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/managing_openshift_ai/creating-custom-workbench-images).

## Update an existing workshop revision

Treat source, image recipes and deployed digests as one reviewed change:

1. Select a full application Git commit in `config/source.lock.json`. `commit`
   selects the chart/notebook files; `buildCommit` selects image inputs.
2. Align each BuildConfig's Git `ref`, source-commit annotation and output tag
   in `manifests/10-images/builds.yaml` with `buildCommit` (tags use its first
   seven characters). YAML is the build source of truth; editing a source lock
   alone does not rewrite BuildConfigs.
3. Run `bash scripts/build-images.sh`, inspect `config/images.params.new`, and
   replace `config/images.params`. Commit the source/YAML/digest updates together
   after verification. The current runbook builds all five images on OpenShift.
4. Back up the participant's notebook files before a content reset. An existing
   PVC deliberately retains edited source; a Helm upgrade alone does not replace it.

For the `user1` pilot, with the target/login already configured as in step 1:

```bash
umask 077
LAB_BACKUP_DIR="$HOME/.config/summit-connect-mlflow-lab/backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LAB_BACKUP_DIR"
chmod 700 "$LAB_BACKUP_DIR"
helm get values tableschnappi -n tableschnappi-user1 -o yaml > "$LAB_BACKUP_DIR/helm-values.yaml"
oc exec user1-0 -c user1 -n tableschnappi-user1 -- \
  tar czf - -C /opt/app-root/src . > "$LAB_BACKUP_DIR/workbench.tar.gz"

# Explicit content reset: removes this participant's project/PVC and app state.
bash scripts/delete-participants.sh --destroy-participant-data 1 1
bash scripts/apply-participants.sh /private/path/model-api-key 1 1
bash scripts/warm-guardrails.sh 1 1
```

For a completely clean participant, including rehearsal history, run
[`reset-mlflow.sh` before deleting its project](TEARDOWN.md#clear-one-workspaces-mlflow-history).
The ordinary project reset above retains the account and shared MLflow data;
prompt seed hooks preserve existing
versions/aliases. Follow the application instructor guide to verify/restore the
intended prompt alias and empty guardrail baseline, then rehearse the workshop
as the real participant. Rebuild/reset only the intended range; provisioning the
full roster is a separate capacity decision. Private backups can contain credentials
or participant data and must stay outside Git. Restore exported notebook edits
selectively; copying the old checkout wholesale would reintroduce old guides.

## Checking changes locally

After configuring site values and an `oc` context, run:

```bash
python3 -m unittest discover -s tests -v
bash scripts/validate.sh 1 50
bash scripts/validate.sh --test
bash scripts/render-participants.sh 1 1 > /tmp/user1-preview.yaml
git diff --check
```

To include the model-update policy tests, run the unit suite with
`uv run --with pyyaml python3 -m unittest discover -s tests -v` (or use an
existing environment with PyYAML).

These commands fetch the pinned public source and render locally. Previewing does
not read model keys or create resources. `oc` requires a configured context even
for local ConfigMap generation. Use the installation's target login; server-side
admission and runtime behavior still need the pilot and rehearsal described in
[validation](VALIDATION.md). Keep site values, source caches and previews out of Git.
