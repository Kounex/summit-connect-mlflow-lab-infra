# Summit Connect MLflow Lab Infrastructure

Prepare OpenShift AI for a one-hour, hands-on MLflow workshop. Each participant
(`user1`–`user50`) gets a restaurant application, Jupyter workbench and MLflow
workspace. A shared, operator-managed MLflow server records traces, prompt
versions and feedback.

The application calls an external OpenAI-compatible model API. This repository
owns infrastructure only. The application repository owns the attendee guides,
notebook and application-specific instructor preparation.

**Start with [the installation runbook](docs/INSTALL.md)** and a single participant.

| Guide | Use it for |
|---|---|
| [Installation](docs/INSTALL.md) | Prerequisites, platform YAML, builds, MLflow, accounts and participant batches |
| [Architecture](docs/DEMO.md) | What runs where; MLflow isolation, instrumentation and model configuration |
| [Attendee workshop](https://github.com/Kounex/tableschnappi/blob/main/workshop/README.md) | Restaurant, prompts, guardrails and final agent notebook (application repo) |
| [Reset and teardown](docs/TEARDOWN.md) | Participant reset, data removal and lab-owned AI uninstall |
| [Validation](docs/VALIDATION.md) | Tested versions, evidence and remaining checks |

## Repository layout

```text
config/                       # Source/image pins and example site values
manifests/
  00-platform/                # AI Subscription, components and model catalog
  10-images/                  # Native Git BuildConfigs and ImageStreams
  20-mlflow/                  # PostgreSQL, S3 storage and MLflow custom resource
  30-participant/project/     # Per-person namespace, quota, limits and grants
  40-accounts/                # Optional existing-Keycloak user definition
  90-operations/              # Warmup, uninstall and specific recovery manifests
scripts/                      # Commands operators run
  helpers/                    # Internal implementations used by entry scripts
docs/                         # Installation, explanation, validation and teardown
```

YAML defines the desired platform/project state. The pinned
[TableSchnappi Helm chart](https://github.com/Kounex/tableschnappi/tree/main/charts/tableschnappi)
defines the restaurant and workbench. Scripts handle ranges, credential transfer,
source packaging, builds and readiness waits. There are no generated per-user
folders to maintain. `.cache/` and `rendered/` are local, ignored output.

## Before installing

This runbook targets OpenShift 4.22 and OpenShift AI `stable-3.5` with Automatic
operator updates. It needs cluster-admin access, an integrated registry,
registry.redhat.io entitlement, cert-manager, default RBD storage and an
ODF/NooBaa object-storage provisioner. It installs AI and the lab on an existing
cluster; it does not provision OpenShift, storage operators or an identity provider.
See [all prerequisites](docs/INSTALL.md#1-configure-the-target).

Copy `config/site-values.example.yaml` to ignored `config/site-values.yaml`.
Keep kubeconfigs, model keys, account receipts and backups outside the repository.
Build images on each new cluster and refresh `config/images.params` before deployment.
The checked-in image digests document the tested build; they do not transfer
images into another cluster's internal registry.

Participant demo credentials use **`userN:userN`**. Restaurant URLs are public,
use synthetic data, and the current guardrail integration fails open on errors.
This is a workshop environment; read the [limitations](docs/DEMO.md#limitations).

One real participant has passed the functional rehearsal. Fifty-user concurrent
capacity, installation without a preinstalled AI operator, and backup restoration
remain [validation gates](docs/VALIDATION.md).

## Application and attendee material

The application, Helm chart and attendee exercises live in
[Kounex/tableschnappi](https://github.com/Kounex/tableschnappi). Open
[the workshop overview](https://github.com/Kounex/tableschnappi/blob/main/workshop/README.md)
for the participant guides and agent playground notebook. The
[implementation explanation](https://github.com/Kounex/tableschnappi/blob/main/docs/IMPLEMENTATION.md)
covers the application/chart changes and their purpose.

TableSchnappi originated with [KiriGould](https://github.com/KiriGould/tableschnappi)
and was extended for MLflow by [Stefan Bergstein](https://github.com/stefan-bergstein/tableschnappi).
This infrastructure repository consumes a pinned application commit; it does not
vendor the application. Its source and image-build commits are recorded separately
in `config/source.lock.json`.

## Resource identity and license

The repository name is independent of deployed resource names. The existing
`darmstadt-demo` ownership label/field manager and `darmstadt-*` shared-storage
names are retained so this runbook can update and remove the deployed lab.
Participant projects remain `tableschnappi-userN`. Renaming the folder does not
migrate or recreate cluster resources.

[MIT license](LICENSE). Optional RHOAI recovery manifests retain their
[version and provenance notes](manifests/90-operations/recovery/README.md).
