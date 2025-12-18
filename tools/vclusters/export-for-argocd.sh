#!/bin/sh
set -eu

VCLUSTER_NAMESPACE="a01-vcluster"
VCLUSTER_NAME="a01-vcluster"

ARGOCD_NAMESPACE="argocd"
SECRET_NAME="cluster-a01-vcluster"
OUT_FILE="./${SECRET_NAME}.yaml"

cfg="$(kubectl -n "$VCLUSTER_NAMESPACE" get secret "vc-$VCLUSTER_NAME" -o jsonpath='{.data.config}' | base64 -d)"

CA="$(printf '%s\n' "$cfg" | awk '/certificate-authority-data:/{print $2; exit}' | tr -d '\r\n')"
CERT="$(printf '%s\n' "$cfg" | awk '/client-certificate-data:/{print $2; exit}' | tr -d '\r\n')"
KEY="$(printf '%s\n' "$cfg" | awk '/client-key-data:/{print $2; exit}' | tr -d '\r\n')"

echo "CA=${#CA} CERT=${#CERT} KEY=${#KEY}" >&2

SERVER="https://${VCLUSTER_NAME}.${VCLUSTER_NAMESPACE}.svc.cluster.local:443"

cat > "$OUT_FILE" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: ${VCLUSTER_NAME}
  server: ${SERVER}
  config: |
    {
      "tlsClientConfig": {
        "caData": "${CA}",
        "certData": "${CERT}",
        "keyData": "${KEY}"
      }
    }
EOF

echo "Wrote ${OUT_FILE}" >&2
