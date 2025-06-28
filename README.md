<div align="center">

<img src="https://raw.githubusercontent.com/kubelize/platform/refs/heads/main/source/assets/logo.png" align="center" width="177px" height="212px"/>

### Infrastructure as Code Kubernetes Clusters

_managed with Flux CD, ArgoCD, Renovate and SideroLabs Omni_

</div>

## Overview

## Kubernetes

### Core Concepts

### Required Componants

**Cilium**

**Flux CD**

**Kyverno**

## GitOps

### Directories

```
.
├── apps #-----------> Operator deployment resources and related addons
│   ├── addons
│   ├── bundles
│   ├── operators
│   └── patches
├── clusters #-------> Kustomizations that deploy apps to a cluster
│   └── cluster-name
├── scripts #--------> Scripts used to automate irreglular tasks
├── source 
│   └── assets
└── staging #--------> Cluster staging manifests
    ├── bootstraps
    └── patches
```

### Fluxcd Workflow

### Renovate

We use renovate to periodically check for available updates to the applications and charts used in this repository. 

### Networking

Cilium is a key componant that provides a feature rich suite of tools that increase the security, ensure connectivity and allow the providing observability of network flows. 

## Cloud Dependencies

### H-Cloud

**SideroLabs Omni**

**Teleport**



