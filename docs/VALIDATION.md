# Validation

Last live checks: **2026-11-16**. The earlier pilot evidence below is dated;
the event-readiness section records the expanded roster. Provisioning and
readiness checks do not establish simultaneous 50-user model capacity.

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
the human account. At the November 12 pilot, only one real attendee account was provisioned. Impersonated
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
At that rehearsal, only user1 was deployed; no extra accounts/stacks were allocated.

Model catalog enablement postdated the full AI-uninstall rehearsal. Catalog namespace provenance
and cleanup are documented in [teardown](TEARDOWN.md); full teardown with the
catalog enabled has not yet been exercised.

## Event readiness — 2026-11-16

The full roster `user1`–`user50` and the identical internal `test` stack are
deployed. Passwords match usernames, including `test:test`; neither first-login
password changes nor administrator access are required.

| Check | Result |
|---|---|
| Roster | 51 accounts, separate projects/workspaces, 255 ready Deployments, 51 ready workbenches and 51 bound 5 GiB notebook PVCs |
| Native identity and content | All 51 workbenches passed source-pin, native MLflow auth, prompt alias, MCP discovery and notebook dependency checks |
| Clean attendee baseline | All 50 attendees have `active` and `baseline` at prompt version 1, empty NeMo input flows, and no active MLflow runs/traces |
| Guardrail warmup | All 51 empty-policy services passed both checks; both requests pass before attendees enable a policy |
| Public app routes | All 51 frontend URLs returned the app and successfully proxied restaurant data and assistant health |
| Real browser identities | `test:test` and `user50:user50` opened MLflow and Jupyter; user50 sees its own project and can access the shared model registry |
| Isolation | Explicit foreign-experiment reads returned `403 PERMISSION_DENIED` for both normal identities; the workspace lists contained only their own workspace |
| Internal rehearsal | Restaurant model/MCP traces, feedback, prompt activation/restoration, allowed/blocked guards and independent notebook agent tracing passed in `test` |
| User1 reset | Private notebook/config/database/workspace exports verified; old notebook PV reclaimed; project recreated, prompt reseeded at version 1 and active history empty |

The user1 reset used the native workspace APIs: prompts/traces were deleted;
renamed experiments and their runs remain in MLflow's soft-deleted history.
Other workspaces and shared services were preserved. The internal test workspace
retains its troubleshooting traces and second prompt version; its active alias
and guardrail configuration were restored to the attendee baseline.

Deployment used bounded groups of four through the normal range entry. First
image pulls on an additional node added startup time; allow the runbook waits
to finish. Readiness checks are read-only and were run across the full roster.
The five schedulable nodes had enough requested CPU/memory for these stacks;
no node scaling was needed. This establishes deployed/idle readiness and an
internal functional rehearsal, **not** 50 simultaneous model/guardrail sessions
or sufficient upstream provider quota.

Local checks cover all 50 attendee renders plus `--test`, chart lint,
shell/Python syntax, local Markdown links, public-file credential scanning and
nine unit tests for target selection, batch failure handling and reset scope.
The full-stack rehearsal remains described in the application repository;
this repository does not duplicate attendee instructions.

## Alternating models — 2026-11-17

The model-update entry now assigns odd users to `qwen38-27b` on the RHDP
endpoint and even users to `publishers/prelude-maas/models/glm-53-flash` on
the second MaaS provider. This gives 25 attendees per provider; `test` stays
on Qwen. Each namespace uses its assigned model/key in the restaurant assistant,
NeMo and workbench. Source profiles contain no credentials.

All 51 namespaces passed the final assignment/key audit, including actual
workbench process environments and retained native MLflow auth. Assistant and
NeMo Deployments were ready and used the expected endpoint/model; there were
25 attendee assignments per provider plus the internal Qwen test stack.

Both providers passed real completions. Qwen passed a restaurant menu/tool turn;
GLM passed the notebook LangGraph agent's menu lookup, with MCP and a trace in
the internal test workspace. This checks compatibility, not answer quality or
simultaneous provider capacity. Human-edited NeMo policy is retained by the
renderer, and model-update hooks do not reseed prompt aliases or clear history.

The operation uses native Helm release values plus profile YAML, SSA Secrets,
explicit consumer restarts and operator-created NeMo resources. The Helm 4.3.2
pilot exposed a renderer plugin requirement and the Notebook CR's restriction
on `spec.template.metadata`; the renderer now uses a supported container env
revision for notebooks. Tests cover that schema regression and retaining an
enabled/custom guardrail policy. Helm 4 updates use client-side three-way merges
to retain live attendee edits without general force-conflict handling.

The local unit suite passes eleven tests with PyYAML, and shell/Python syntax
checks pass. Private before-change snapshots include release values, guardrail
configuration and model Secrets. Keys remain outside the public repository.
See [the repeatable update command](INSTALL.md#change-models-on-existing-stacks).

## GLM rate-limit split — 2026-11-17

The former 25-person GLM cohort was split again: users divisible by four moved
to `qwen38-27b` with a **second Qwen key**; the remaining even users stayed on
GLM. The original odd-user Qwen key and internal test stack were unchanged.
This leaves 25 attendees on the primary Qwen credential, 12 on the second Qwen
credential and 13 on GLM; `test` additionally uses primary Qwen.

The new key passed a real completion before rollout. The explicit-name update
used the same Helm/policy-preserving process on only user4, user8, …, user48.
Updates now apply all selected configurations before the wait phase, so one
workbench restart does not postpone remaining restaurant model changes. Native
controller revision checks, rollout waits and NeMo warmup passed for the targets.
The runbook records the base assignment plus this overlay for replay. Attendee
policy edits were left intact.

## Remaining gates

1. Rehearse simultaneous workbench/model/guardrail load across the roster.
   Use the application workshop's current questions and
   agent experiments to size model and guard calls; one turn can make multiple
   provider requests. Check CPU, memory and provider quota.
2. Exercise installation on a target without a bootstrapped AI operator. The
   replay began with an operator-only installation and no AI workloads.
3. Verify database/password/artifact backup restoration if retaining history.
   Private backups were taken; the replay intentionally started with clean data.
4. Rehearse complete teardown with the model catalog enabled.

Stable-channel operator updates are accepted by this demo's policy. Later
versions need a new rehearsal before describing them as tested.
