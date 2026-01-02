# Velero Backup Configuration

This directory contains Velero backup and disaster recovery configuration.

## Overview

Velero provides:
- Automated backup schedules
- Disaster recovery capabilities
- Cluster migration support
- PVC/volume snapshots

## Backup Schedules

Three backup schedules are configured:

1. **daily-backup**: Full cluster backup at 2 AM daily, retained for 30 days
2. **weekly-backup**: Full cluster backup weekly (Sunday 3 AM), retained for 90 days
3. **critical-hourly**: Hourly backups of critical namespaces (argocd, vault, sdtd), retained for 7 days

## Configuration Required

### Per-Cluster Setup

Each cluster needs:

1. **S3 Credentials Secret**
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: velero-credentials
     namespace: velero
   type: Opaque
   stringData:
     cloud: |
       [default]
       aws_access_key_id=<YOUR_ACCESS_KEY>
       aws_secret_access_key=<YOUR_SECRET_KEY>
   ```

2. **Backup Storage Location Patch**
   - Configure S3 endpoint URL
   - Set bucket name
   - Configure region

### Example: MinIO Configuration

If using MinIO as S3-compatible storage:

```yaml
configuration:
  backupStorageLocation:
    - name: default
      provider: aws
      bucket: velero-backups
      config:
        region: us-east-1
        s3ForcePathStyle: "true"
        s3Url: "http://minio.storage.svc.cluster.local:9000"
```

### Example: AWS S3 Configuration

```yaml
configuration:
  backupStorageLocation:
    - name: default
      provider: aws
      bucket: my-velero-backups
      config:
        region: us-west-2
```

## Usage

### Create Manual Backup

```bash
# Backup entire cluster
velero backup create full-backup-$(date +%Y%m%d) --wait

# Backup specific namespace
velero backup create sdtd-backup --include-namespaces sdtd --wait

# Backup with volume snapshots
velero backup create pvc-backup --include-namespaces sdtd --snapshot-volumes --wait
```

### Restore from Backup

```bash
# List backups
velero backup get

# Restore entire backup
velero restore create --from-backup daily-backup-20260101020000

# Restore specific namespace
velero restore create --from-backup daily-backup-20260101020000 \
  --include-namespaces sdtd

# Restore and map to new namespace
velero restore create --from-backup sdtd-backup \
  --namespace-mappings sdtd:sdtd-restored
```

### View Backup Details

```bash
# Get backup status
velero backup describe daily-backup-20260101020000

# View backup logs
velero backup logs daily-backup-20260101020000

# Get restore status
velero restore describe <restore-name>
```

### Schedule Management

```bash
# List schedules
velero schedule get

# Pause schedule
velero schedule pause daily-backup

# Unpause schedule
velero schedule unpause daily-backup
```

## Integration with SDTD Server Backups

The `critical-hourly` schedule includes the `sdtd` namespace for frequent backups of your game server. This complements the manual backup script in `/tools/sdtd-backup.sh`.

**Recommended Strategy:**
- Use Velero for automated Kubernetes resource backups
- Use the manual script for clean, offline backups before major updates
- Velero provides quick recovery for accidental deletions or cluster failures
- Manual backups provide guaranteed clean game state

## Monitoring

Check backup status in ArgoCD or via CLI:

```bash
# Check recent backups
velero backup get

# Check failed backups
velero backup get --selector='velero.io/backup-status=Failed'

# Check backup storage location status
velero backup-location get
```

## Troubleshooting

### Backup Failing

1. Check credentials:
   ```bash
   kubectl get secret -n velero velero-credentials -o yaml
   ```

2. Check backup storage location:
   ```bash
   velero backup-location get
   kubectl describe backupstoragelocation -n velero default
   ```

3. Check logs:
   ```bash
   kubectl logs -n velero deployment/velero
   ```

### Storage Unavailable

If S3 storage is unavailable, backups will fail. Verify:
- S3 endpoint is reachable
- Credentials are correct
- Bucket exists and is accessible
- Network connectivity from cluster to S3

## Security

- Credentials are stored in Kubernetes secrets
- Consider using SOPS/sealed-secrets for credential encryption at rest
- For AWS, consider using IRSA (IAM Roles for Service Accounts)
- Ensure S3 buckets have appropriate access policies
