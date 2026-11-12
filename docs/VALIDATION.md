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
| Prompt comparison | Five baseline and five candidate restaurant turns; two stored comparison runs/artifacts with prompt versions and app trace links |
| Prompt lifecycle / feedback | UI create, activate and restore passed; prompt lineage, session metadata and `user_rating` persisted |
| Workspace isolation | Human account could read its workspace; explicit foreign experiment read returned `403 PERMISSION_DENIED` |
| Policy permissions | Impersonated participant checks allowed own ConfigMap editing and NeMo restart |
| Guardrails | Warmed menu request allowed; off-topic request blocked before agent/tools without fail-open; empty policy restored and warmed |
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

Application checks also passed: 11 chart regression checks, seven assistant
regressions and 50 native project/chart renders. Their scope is documented in
the [application validation notes](https://github.com/Kounex/tableschnappi/blob/main/docs/VALIDATION.md).

The immutable workbench base has an existing Ray/codeflare dependency conflict.
Adding lab packages introduced no new conflicts; the Dockerfile compares checks
before and after installation. Those distributed-computing features are outside
this lab. Diagnostic response-format checks are observations, not correctness
scores or guaranteed model behavior.

## Teardown coverage

Participant reset and complete lab/AI removal were exercised. RHOAI 3.5.2 removed
a controller before finalizing its LLM configuration objects. The checked-in
[recovery manifests](../manifests/90-operations/recovery/README.md) restored the
native controller, which finalized them normally. No finalizers were stripped.
Residual resources were audited against the original cluster inventory.

The model catalog was enabled after that rehearsal. Catalog namespace provenance
and cleanup are documented in [teardown](TEARDOWN.md); full teardown with the
catalog enabled has not yet been exercised.

## Remaining gates

1. Deploy the full roster and rehearse simultaneous workbench/model/guardrail
   load. Two five-case batches per attendee mean at least 500 restaurant turns,
   plus tool and guard model calls. Check CPU, memory and provider quota.
2. Rehearse as a second real identity, including cross-workspace denial.
3. Exercise installation on a target without a bootstrapped AI operator. The
   replay began with an operator-only installation and no AI workloads.
4. Verify database/password/artifact backup restoration if retaining history.
   Private backups were taken; the replay intentionally started with clean data.
5. Rehearse complete teardown with the model catalog enabled.

Stable-channel operator updates are accepted by this demo's policy. Later
versions need a new rehearsal before describing them as tested.
