# RHOAI 3.5.2 LLM configuration cleanup recovery

Use this **only** when the native AI uninstall has already deleted the
controller, `redhat-ods-applications` is Terminating, and its remaining content
is `LLMInferenceServiceConfig` objects with
`serving.kserve.io/llmisvcconfig-finalizer`. Check namespace conditions and all
LLMInferenceServices first. This procedure was exercised during the cluster
move; it does not remove finalizers manually.

The manifests restore the exact digest-pinned RHOAI 3.5.2 LLM controller, its
native RBAC and a fresh service-CA certificate in temporary namespace
`darmstadt-ai-cleanup`. They were derived from the installed 3.5.2 controller.
The controller checks for referencing services and performs its normal cleanup.
All cluster-scoped recovery bindings/roles have explicit `darmstadt-cleanup-`
names and ownership labels. No cluster-admin grant or copied private key is used.

```bash
# Use the dedicated target kubeconfig and EXPECTED_API_SERVER.
source scripts/helpers/check-target.sh
oc get namespace redhat-ods-applications -o jsonpath='{.status.conditions}'
oc get llminferenceservices -A
oc get llminferenceserviceconfigs -n redhat-ods-applications
# Inspect these three files, then apply in order:
oc apply --server-side --field-manager=darmstadt-demo-recovery -f manifests/90-operations/recovery/namespace.yaml
oc apply --server-side --field-manager=darmstadt-demo-recovery -f manifests/90-operations/recovery/rbac.yaml
oc apply --server-side --field-manager=darmstadt-demo-recovery -f manifests/90-operations/recovery/controller.yaml
oc rollout status deployment/llmisvc-controller-manager -n darmstadt-ai-cleanup --timeout=300s
oc logs deployment/llmisvc-controller-manager -n darmstadt-ai-cleanup
oc wait --for=delete namespace/redhat-ods-applications --timeout=600s
```

The rehearsal's 20 objects used stored API version `v1alpha2`. No conversion
webhook or finalizer edits were required. Check logs rather than applying this
blindly to another release or different remaining resource kinds. If a config
is still referenced, delete the authorized dependent model/service first.

After the AI application namespace is gone, remove **all** recovery resources:

```bash
oc delete -f manifests/90-operations/recovery/controller.yaml --wait=true
oc delete -f manifests/90-operations/recovery/rbac.yaml --wait=true
oc delete -f manifests/90-operations/recovery/namespace.yaml --wait=true
oc get clusterrole,clusterrolebinding -l event.redhat.com/purpose=uninstall-controller-recovery
```

Then finish the normal operator-namespace and residual-resource checks in
[TEARDOWN.md](../../../docs/TEARDOWN.md). Never delete the CRD while its instances
or the recovery controller still need it.
