# Validation

Last live rehearsal: **2026-11-12**. One real participant (`user1`) passed the
functional checks. This is evidence for the pilot, not a 50-user capacity result.

## Tested configuration

| Component | Tested configuration |
|---|---|
| OpenShift / OpenShift AI | OpenShift 4.22; RHOAI 3.5.2, Subscription `stable-3.5`, Automatic approval |
| MLflow | Operator-managed server 3.14; workbench SDK 3.17.1 |
| Model | External OpenAI-compatible API, `qwen36-35b-a3b` |
| Application/chart source | Exact source and build commits in `config/source.lock.json` |
| Images | Immutable digests in `config/images.params`; rebuild and refresh for a new cluster |

## Evidence

| Check | Result |
|---|---|
| Builds and deployment | Five native Git image builds completed; native project YAML and pinned Helm release installed |
| Account lifecycle | The range command `1 1` created a real account; delete/recreate and `userN:userN` credential enforcement passed |
| Participant reset | Namespace, notebook PVC/PV and external pull grant removed; reinstall retained shared MLflow history |
| SSO and workbench | Real participant opened MLflow/Jupyter; native connection/auth injection and gateway TLS passed; notebook dependencies were ready |
| Workspace isolation | Human account could read its workspace; explicit foreign experiment read returned `403 PERMISSION_DENIED` |
| Model catalog | Real participant browsed cards/filters; impersonated user1/user50 could read catalog Service/Endpoints, not namespace Secrets or catalog source configuration |
| Cluster move | Removed the old lab/AI installation, preserved unrelated applications/storage/identities and recreated the pilot on another cluster |

The notebook executes as its service account; browser SSO/isolation checks used
the human account. Only one real attendee account was provisioned. Impersonated
RBAC checks do not demonstrate a second participant's complete login journey.

Publication preparation also passed from a clean copy using only public files
and the example site values: all 50 participant renders, chart lint, shell/Python
syntax and local Markdown links. The complete user1 preview rendered with an
unreachable test API address; no cluster access was needed. `oc` still needs a
configured context for its local ConfigMap generation.

Application behavior, agent dependencies and image compatibility checks are
recorded in the [application validation notes](https://github.com/Kounex/tableschnappi/blob/main/docs/VALIDATION.md).
The infrastructure checks establish project/config rendering, deployment,
storage, account lifecycle and access boundaries. They do not establish model
answer quality or simultaneous capacity.

## Shared model registry — 2026-11-12

The lab now declares `ModelRegistry/summit-connect` separately from the model
catalog, using native `postgres.generateDeployment: true`. The operator creates
its database, generated credentials and 5 GiB PVC. The registry and PostgreSQL
Deployments are ready. Server-side apply is repeatable with no remaining diff.

Real `user1:user1` browser SSO opens **AI hub → Models → Registry**, lists the
empty registry and opens its Register model form. No synthetic model records
were added. Impersonated checks for user1/user50 allow `get` on the named registry
Service/Endpoints and deny Secrets/registry creation. Those checks did not create
another attendee account. The group policy is `system:authenticated`; metadata
in this registry is shared, independently of MLflow workspace isolation.

Deletion/recreation of the empty registry was exercised with its operator still
running. The native finalizer removed its Group and gateway HTTPRoute; owned
resources, PVC and the Delete-policy RBD PV disappeared. RHOAI 3.5.2 retained the
cluster-scoped auth-delegator binding. Its saved UID, native labels, role and
service-account subject were checked before deleting that specific binding.
The registry was then recreated and its access binding applied. The receipt is
local/ignored; the exact cleanup is in [teardown](TEARDOWN.md#model-catalog-and-registry-namespace).
This validates instance teardown, not complete AI uninstall with catalog/registry.

## Teardown coverage

Participant reset and complete lab/AI removal were exercised. RHOAI 3.5.2 removed
a controller before finalizing its LLM configuration objects. The checked-in
[recovery manifests](../manifests/90-operations/recovery/README.md) restored the
native controller, which finalized them normally. No finalizers were stripped.
Residual resources were audited against the original cluster inventory.

## Updated pilot deployment — 2026-11-12

Both repository PRs were merged. Native Git builds completed for all five images
from `buildCommit` in `config/source.lock.json`; the digest lock was refreshed.
The pilot was backed up privately and recreated with the normal explicit `1 1`
delete/apply/warm entry commands. Its account and shared MLflow history remained.
The Notebook, source ConfigMap and PVC checkout match the selected `commit`.

Source and image-input commits differ intentionally: the live rehearsal found
a UTF-8 decoder issue in the notebook's source-only MCP helper. The corrected
source was repackaged and the pilot recreated without rebuilding unchanged image
recipes. The workbench dependency build passed its base-image conflict check.
Native auth/Secret references, readiness and real participant browser access pass.
Final prompt/guardrail baseline restoration and warmup also pass.

The application-specific scenario results are maintained only in
[TableSchnappi's validation notes](https://github.com/Kounex/tableschnappi/blob/main/docs/VALIDATION.md).
The reproducible backup/build/reset procedure is in
[updating an existing workshop](INSTALL.md#update-an-existing-workshop-revision).
Only user1 was deployed; no extra participant accounts/stacks were allocated.

Model catalog enablement postdated the full AI-uninstall rehearsal. Catalog namespace provenance
and cleanup are documented in [teardown](TEARDOWN.md); full teardown with the
catalog enabled has not yet been exercised.

## Remaining gates

1. Deploy the full roster and rehearse simultaneous workbench/model/guardrail
   load. Use the application workshop's current questions and
   agent experiments to size model and guard calls; one turn can make multiple
   provider requests. Check CPU, memory and provider quota.
2. Rehearse as a second real identity, including cross-workspace denial.
3. Exercise installation on a target without a bootstrapped AI operator. The
   replay began with an operator-only installation and no AI workloads.
4. Verify database/password/artifact backup restoration if retaining history.
   Private backups were taken; the replay intentionally started with clean data.
5. Rehearse complete teardown with the model catalog enabled.

Stable-channel operator updates are accepted by this demo's policy. Later
versions need a new rehearsal before describing them as tested.
