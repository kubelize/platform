#!/bin/bash
# SDTD Server Backup Script
# Backs up world and player data from the SDTD server

set -e

NAMESPACE="sdtd"
DEPLOYMENT="a01-sdtd-prod-game-servers"
BACKUP_DIR="${HOME}/sdtd-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="sdtd-backup-${TIMESTAMP}"

echo "=== SDTD Server Backup ==="
echo "Timestamp: ${TIMESTAMP}"
echo "Backup directory: ${BACKUP_DIR}/${BACKUP_NAME}"
echo ""

# Create backup directory
mkdir -p "${BACKUP_DIR}/${BACKUP_NAME}"

# Get the pod name
POD=$(kubectl get pod -n ${NAMESPACE} -l app.kubernetes.io/instance=a01-sdtd-prod,app.kubernetes.io/name=game-servers -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD" ]; then
  echo "Error: Could not find running pod for deployment ${DEPLOYMENT}"
  exit 1
fi

echo "Found pod: ${POD}"
echo ""

# Save the world first to ensure data is written to disk
echo "Triggering world save..."
kubectl exec -n ${NAMESPACE} ${POD} -- bash -c 'echo "saveworld" > /tmp/server_input.txt' || echo "Warning: Could not trigger save command"
sleep 5

echo ""
echo "Scaling down deployment to ensure clean backup..."
kubectl scale deployment/${DEPLOYMENT} -n ${NAMESPACE} --replicas=0
echo "Waiting for pod to terminate..."
kubectl wait --for=delete pod/${POD} -n ${NAMESPACE} --timeout=120s || true
sleep 5

echo ""
echo "Starting backup process..."
echo "Note: Server is currently stopped. Will restart after backup."
echo ""

# Since pod is stopped, we need to use a temporary pod to access the PVC
echo "Creating temporary backup pod..."
kubectl run sdtd-backup-temp -n ${NAMESPACE} --image=busybox --restart=Never --overrides='
{
  "spec": {
    "containers": [{
      "name": "backup",
      "image": "busybox:latest",
      "command": ["sleep", "300"],
      "volumeMounts": [{
        "name": "storage",
        "mountPath": "/data"
      }]
    }],
    "volumes": [{
      "name": "storage",
      "persistentVolumeClaim": {
        "claimName": "a01-sdtd-prod"
      }
    }]
  }
}'

echo "Waiting for backup pod to be ready..."
kubectl wait --for=condition=ready pod/sdtd-backup-temp -n ${NAMESPACE} --timeout=60s

# Backup critical game data
echo ""
echo "Backing up world and player data..."
kubectl exec -n ${NAMESPACE} sdtd-backup-temp -- tar -czf /tmp/saves-backup.tar.gz -C /data Saves
kubectl cp ${NAMESPACE}/sdtd-backup-temp:/tmp/saves-backup.tar.gz "${BACKUP_DIR}/${BACKUP_NAME}/saves-backup.tar.gz"
kubectl exec -n ${NAMESPACE} sdtd-backup-temp -- rm /tmp/saves-backup.tar.gz

echo "Backing up server configurations..."
kubectl cp ${NAMESPACE}/sdtd-backup-temp:/data/serverconfig.xml "${BACKUP_DIR}/${BACKUP_NAME}/serverconfig.xml" || echo "Warning: serverconfig.xml not found"
kubectl cp ${NAMESPACE}/sdtd-backup-temp:/data/serveradmin.xml "${BACKUP_DIR}/${BACKUP_NAME}/serveradmin.xml" || echo "Warning: serveradmin.xml not found"
kubectl cp ${NAMESPACE}/sdtd-backup-temp:/data/sdtdconfig.xml "${BACKUP_DIR}/${BACKUP_NAME}/sdtdconfig.xml" || echo "Warning: sdtdconfig.xml not found"

# Cleanup and restart
echo ""
echo "Cleaning up backup pod..."
kubectl delete pod sdtd-backup-temp -n ${NAMESPACE}

echo "Restarting SDTD server..."
kubectl scale deployment/${DEPLOYMENT} -n ${NAMESPACE} --replicas=1
Original Pod: ${POD}

Backup Process:
- Server was stopped before backup to ensure data consistency
- All in-memory data was flushed to disk
- Clean snapshot of world state

Contents:
- saves-backup.tar.gz: World and player data from Saves directory
- serverconfig.xml: Server configuration
- serveradmin.xml: Admin list
- sdtdconfig.xml: Additional server config

To restore:
1. Scale down deployment: kubectl scale deployment/${DEPLOYMENT} -n ${NAMESPACE} --replicas=0
2. Wait for pod to terminate
3. Create restore pod (similar to backup process)
4. Extract saves-backup.tar.gz to /home/kubelize/server/
5. Copy config files back to /home/kubelize/server/
6. Scale up deployment: kubectl scale deployment/${DEPLOYMENT} -n ${NAMESPACE} --replicas=1
Contents:
- saves-backup.tar.gz: World and player data from Saves directory
- serverconfig.xml: Server configuration
- serveradmin.xml: Admin list
- sdtdconfig.xml: Additional server config

To restore:
1. Extract saves-backup.tar.gz to /home/kubelize/server/
2. Copy config files back to /home/kubelize/server/
3. Restart the server
EOF

# Get backup size
BACKUP_SIZE=$(du -sh "${BACKUP_DIR}/${BACKUP_NAME}" | cut -f1)

echo ""
echo "=== Backup Complete ==="
echo "Location: ${BACKUP_DIR}/${BACKUP_NAME}"
echo "Size: ${BACKUP_SIZE}"
echo ""
echo "Files backed up:"
ls -lh "${BACKUP_DIR}/${BACKUP_NAME}"
echo ""
echo "To compress entire backup:"
echo "  cd ${BACKUP_DIR} && tar -czf ${BACKUP_NAME}.tar.gz ${BACKUP_NAME}"
