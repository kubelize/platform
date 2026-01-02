#!/bin/bash
# Velero Setup Helper Script
# This script helps configure Velero for a specific cluster

set -e

CLUSTER_NAME=""
S3_PROVIDER=""
S3_BUCKET=""
S3_ENDPOINT=""
S3_REGION=""
AWS_ACCESS_KEY=""
AWS_SECRET_KEY=""

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Velero Cluster Configuration Helper ==="
echo ""

# Get cluster name
read -p "Cluster name (e.g., kubelize-core, home-dhe): " CLUSTER_NAME
if [ -z "$CLUSTER_NAME" ]; then
  echo -e "${RED}Error: Cluster name is required${NC}"
  exit 1
fi

CLUSTER_PATH="clusters/${CLUSTER_NAME}"
if [ ! -d "$CLUSTER_PATH" ]; then
  echo -e "${RED}Error: Cluster directory ${CLUSTER_PATH} not found${NC}"
  exit 1
fi

echo ""
echo "Select S3 provider:"
echo "1) MinIO (self-hosted)"
echo "2) AWS S3"
echo "3) Wasabi"
echo "4) Other S3-compatible"
read -p "Selection [1-4]: " PROVIDER_CHOICE

case $PROVIDER_CHOICE in
  1)
    S3_PROVIDER="minio"
    read -p "MinIO endpoint (e.g., http://minio.storage.svc.cluster.local:9000): " S3_ENDPOINT
    read -p "Bucket name [velero-backups]: " S3_BUCKET
    S3_BUCKET=${S3_BUCKET:-velero-backups}
    S3_REGION="us-east-1"
    ;;
  2)
    S3_PROVIDER="aws"
    read -p "S3 bucket name: " S3_BUCKET
    read -p "AWS region [us-west-2]: " S3_REGION
    S3_REGION=${S3_REGION:-us-west-2}
    S3_ENDPOINT=""
    ;;
  3)
    S3_PROVIDER="wasabi"
    read -p "Bucket name: " S3_BUCKET
    read -p "Wasabi region [us-east-1]: " S3_REGION
    S3_REGION=${S3_REGION:-us-east-1}
    S3_ENDPOINT="https://s3.${S3_REGION}.wasabisys.com"
    ;;
  4)
    S3_PROVIDER="custom"
    read -p "S3-compatible endpoint URL: " S3_ENDPOINT
    read -p "Bucket name: " S3_BUCKET
    read -p "Region [us-east-1]: " S3_REGION
    S3_REGION=${S3_REGION:-us-east-1}
    ;;
  *)
    echo -e "${RED}Invalid selection${NC}"
    exit 1
    ;;
esac

# Get credentials
echo ""
echo -e "${YELLOW}S3 Credentials${NC}"
read -p "AWS Access Key ID: " AWS_ACCESS_KEY
read -sp "AWS Secret Access Key: " AWS_SECRET_KEY
echo ""

if [ -z "$AWS_ACCESS_KEY" ] || [ -z "$AWS_SECRET_KEY" ]; then
  echo -e "${RED}Error: Credentials are required${NC}"
  exit 1
fi

# Create directories
mkdir -p "${CLUSTER_PATH}/config/secrets/velero"
mkdir -p "${CLUSTER_PATH}/patches"

# Create credentials secret
echo ""
echo -e "${GREEN}Creating credentials secret...${NC}"
cat > "${CLUSTER_PATH}/config/secrets/velero/velero-credentials.yaml" <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: velero-credentials
  namespace: velero
type: Opaque
stringData:
  cloud: |
    [default]
    aws_access_key_id=${AWS_ACCESS_KEY}
    aws_secret_access_key=${AWS_SECRET_KEY}
EOF

# Create storage location patch
echo -e "${GREEN}Creating storage location patch...${NC}"
if [ "$S3_PROVIDER" = "minio" ] || [ "$S3_PROVIDER" = "custom" ]; then
  cat > "${CLUSTER_PATH}/patches/velero-storage.yaml" <<EOF
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: velero
  namespace: argocd
spec:
  sources:
    - repoURL: https://vmware-tanzu.github.io/helm-charts
      targetRevision: 7.2.1
      chart: velero
      helm:
        valuesObject:
          configuration:
            backupStorageLocation:
              - name: default
                provider: aws
                bucket: ${S3_BUCKET}
                config:
                  region: ${S3_REGION}
                  s3ForcePathStyle: "true"
                  s3Url: "${S3_ENDPOINT}"
EOF
else
  cat > "${CLUSTER_PATH}/patches/velero-storage.yaml" <<EOF
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: velero
  namespace: argocd
spec:
  sources:
    - repoURL: https://vmware-tanzu.github.io/helm-charts
      targetRevision: 7.2.1
      chart: velero
      helm:
        valuesObject:
          configuration:
            backupStorageLocation:
              - name: default
                provider: aws
                bucket: ${S3_BUCKET}
                config:
                  region: ${S3_REGION}
EOF
fi

# Update kustomization files
echo -e "${GREEN}Updating kustomization files...${NC}"

# Add secret to secrets kustomization
if ! grep -q "velero/velero-credentials.yaml" "${CLUSTER_PATH}/config/secrets/kustomization.yaml" 2>/dev/null; then
  if [ -f "${CLUSTER_PATH}/config/secrets/kustomization.yaml" ]; then
    # Append to existing file
    sed -i '' '/^resources:/a\
  - velero/velero-credentials.yaml
' "${CLUSTER_PATH}/config/secrets/kustomization.yaml"
  fi
fi

# Add patch to cluster kustomization
if [ -f "${CLUSTER_PATH}/kustomization.yaml" ]; then
  if ! grep -q "velero-storage.yaml" "${CLUSTER_PATH}/kustomization.yaml" 2>/dev/null; then
    echo ""
    echo -e "${YELLOW}Manual step required:${NC}"
    echo "Add the following to ${CLUSTER_PATH}/kustomization.yaml under 'patches':"
    echo ""
    echo "  - path: patches/velero-storage.yaml"
    echo "    target:"
    echo "      kind: Application"
    echo "      name: velero"
  fi
fi

# Encrypt with SOPS if available
if command -v sops &> /dev/null; then
  echo ""
  read -p "Encrypt credentials with SOPS? [Y/n]: " ENCRYPT
  ENCRYPT=${ENCRYPT:-Y}
  if [[ $ENCRYPT =~ ^[Yy] ]]; then
    echo -e "${GREEN}Encrypting credentials...${NC}"
    sops -e -i "${CLUSTER_PATH}/config/secrets/velero/velero-credentials.yaml"
    echo -e "${GREEN}Credentials encrypted${NC}"
  fi
else
  echo ""
  echo -e "${YELLOW}Warning: SOPS not found. Please encrypt the credentials manually:${NC}"
  echo "  sops -e -i ${CLUSTER_PATH}/config/secrets/velero/velero-credentials.yaml"
fi

echo ""
echo -e "${GREEN}=== Configuration Complete ===${NC}"
echo ""
echo "Files created:"
echo "  - ${CLUSTER_PATH}/config/secrets/velero/velero-credentials.yaml"
echo "  - ${CLUSTER_PATH}/patches/velero-storage.yaml"
echo ""
echo "Next steps:"
echo "1. Review and commit the configuration"
echo "2. Ensure patches are referenced in ${CLUSTER_PATH}/kustomization.yaml"
echo "3. Push to trigger ArgoCD sync"
echo "4. Verify deployment: kubectl get pods -n velero"
echo "5. Test backup: velero backup create test-backup --wait"
echo ""
