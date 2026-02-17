<div align="center">

<img src="https://raw.githubusercontent.com/kubelize/platform/refs/heads/prod/source/assets/logo.png" align="center" width="177px" height="212px"/>

### Infrastructure as Code Kubernetes Clusters

_managed with Flux CD, ArgoCD, Renovate and SideroLabs Omni_

</div>

## Overview

This repository defines cluster lifecycle, GitOps bootstrap, and platform apps for multiple Kubernetes environments.

Control flow:

1. Omni cluster definitions in `staging/` create Talos clusters and apply inline bootstrap manifests.
2. Bootstrap manifests install Flux resources that reconcile this repository.
3. Flux installs Argo CD from `apps/operators/gitops/argocd/`.
4. Argo CD Applications in `clusters/<cluster>/config/` deploy cluster bundles, features, and external project repos.

## Prerequisites

Required CLI tools:

- `omnictl`
- `kustomize`
- `kubectl`
- `sops`
- `gpg`
- `ejson`

Optional but useful:

- `argocd`
- `flux`

## Kubernetes

### Core Concepts

- **Talos + Omni for machine lifecycle**: cluster specs are in `staging/*.yaml` with patches in `staging/patches/`.
- **Flux as bootstrap reconciler**: first-layer `GitRepository` + `Kustomization` objects come from `staging/bootstraps/*.yaml`.
- **Argo CD as app orchestrator**: app-of-apps definitions live in `clusters/*/config/`.
- **Kustomize overlays per environment**: cluster-specific composition is in `clusters/*/kustomization.yaml`.
- **Encrypted secrets in Git**: SOPS-encrypted Kubernetes secrets and EJSON payloads are rendered by a custom Argo CD CMP plugin.

### Core Platform Components

Current bundles/manifests include:

- Cilium
- cert-manager
- ingress-nginx
- metrics-server
- kube-prometheus-stack
- Teleport kube-agent
- CSI Proxmox + Proxmox storage classes
- CSI NFS + NFS storage classes
- Velero
- Crossplane
- CloudNativePG (CNPG)
- Argo CD + Flux CD

## GitOps

### Repository Layout

```text
.
├── apps/                # Reusable platform apps and bundles
│   ├── addons/          # Supporting resources (issuers, storageclasses, credentials, etc.)
│   ├── bundles/         # Grouped app sets (core-r1, vcluster-r1, package bundles)
│   ├── features/        # Higher-level feature stacks (crossplane, vault, cnpg, etc.)
│   └── operators/       # ArgoCD Application definitions and operator manifests
├── clusters/            # Cluster-specific composition, patches, overlays, and config apps
├── common/              # Shared patches (for example ArgoCD Application sync policy)
├── source/assets/       # Branding assets
├── staging/             # Omni cluster definitions, bootstrap inline manifests, Talos patches
└── tools/               # Utility scripts and helpers
```

### Bootstrap Workflow

Sync a cluster template to Omni:

```bash
omnictl cluster template sync -f staging/<cluster>.yaml
```

Example:

```bash
omnictl cluster template sync -f staging/home-mck.yaml
```

For each cluster, bootstrap definitions in `staging/bootstraps/*.yaml` create Flux resources like:

- `GitRepository` named `platform` pointing to this repo
- `Kustomization` named `argocd` (path `./apps/operators/gitops/argocd/`)
- `Kustomization` named `platform` (cluster config path `./clusters/<cluster>/config/`)

Depending on cluster/environment, additional `GitRepository` and `Kustomization` resources (for example external secrets repos) can also be included in bootstrap manifests.

After Flux applies Argo CD, cluster config apps in `clusters/<cluster>/config/` take over:

- `bootstrap` Application points Argo CD to `clusters/<cluster>/`
- `projects` Application points Argo CD to external `kubelize/projects`

### Cluster Composition

Typical flow for a cluster:

1. Edit `clusters/<cluster>/kustomization.yaml` to choose bundles/features and local patches.
2. Put cluster app roots in `clusters/<cluster>/config/` (`bootstrap.yaml`, `projects.yaml`, `secrets/`).
3. Add environment values in `subst.yaml` and optional overlay files.
4. Commit and push; Flux and Argo CD reconcile automatically.

## Cloud Dependencies

Required:

- SideroLabs Omni (cluster lifecycle and Talos orchestration)
- Proxmox (storage and infrastructure integrations)

Optional / feature-dependent:

- Teleport (secure cluster/application access)
- S3-compatible object storage (Velero backups)

## Secrets and Encryption

### SOPS

- SOPS rules are in `.sops.yaml`.
- Public key is in `publickey.asc`.
- Encrypted Kubernetes secrets live in paths like `clusters/*/config/secrets/**/*.yaml`.
- Flux Kustomizations use `decryption.provider: sops` with secret `sops-gpg`.
- Never commit plaintext secrets. Encrypt before commit.

### EJSON + Substitution Plugin

- Argo CD repo-server runs custom CMP plugin `kubelize/subst-cmp`.
- Plugin config is `apps/operators/gitops/argocd/subst-cmp-configmap.yaml`.
- It discovers `subst.yaml` files and renders templates with EJSON-backed values.
- EJSON key material is delivered through `apps/addons/ejson/ejson-keys.yaml` (SOPS-encrypted).

## Renovate

Renovate is configured in `renovate.json5` to:

- scan YAML/YML manifests,
- group minor/patch updates,
- allow major Docker updates.

## Tooling

Useful helper scripts:

- `tools/setup-velero.sh`: scaffold per-cluster Velero credentials/patches.
- `tools/vclusters/export-for-argocd.sh`: export vcluster kubeconfig into an Argo CD cluster secret.
- `tools/sdtd-backup.sh`: backup helper script.

## New Cluster Checklist

1. Create or update a cluster template in `staging/<cluster>.yaml`.
2. Sync it to Omni with `omnictl cluster template sync -f staging/<cluster>.yaml`.
3. Add or update bootstrap inline manifests in `staging/bootstraps/<cluster>.yaml`.
4. Create `clusters/<cluster>/kustomization.yaml` and select bundles/features/patches.
5. Create `clusters/<cluster>/config/` with at least `bootstrap.yaml` and `projects.yaml`.
6. Add `clusters/<cluster>/subst.yaml` and overlay-specific substitution files as needed.
7. Add encrypted secrets under `clusters/<cluster>/config/secrets/` (SOPS and/or EJSON flow).
8. Validate manifests locally with `kustomize build --load-restrictor LoadRestrictionsNone`.
9. Commit and push; verify Flux and Argo CD reconciliation.

## Quick Validation

Before pushing, you can sanity-check manifests locally:
Run these from the repository root.

```bash
# Build a cluster composition
kustomize build --load-restrictor LoadRestrictionsNone clusters/<cluster>

# Build cluster bootstrap config app set
kustomize build --load-restrictor LoadRestrictionsNone clusters/<cluster>/config

# Build Argo CD operator resources
kustomize build --load-restrictor LoadRestrictionsNone apps/operators/gitops/argocd
```
