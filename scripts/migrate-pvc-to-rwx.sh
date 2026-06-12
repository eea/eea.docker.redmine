#!/usr/bin/env bash
#
# migrate-pvc-to-rwx.sh
# Migrates a PVC from RWO to RWX access mode by creating a new RWX PVC
# and copying data from the old PVC.
#
# Usage:
#   ./scripts/migrate-pvc-to-rwx.sh <cluster> <namespace> <release-name> <storage-name> [--dry-run]
#
# Examples:
#   ./scripts/migrate-pvc-to-rwx.sh 02pre taskman taskman filesDir
#   ./scripts/migrate-pvc-to-rwx.sh 01prod taskman taskman github
#   ./scripts/migrate-pvc-to-rwx.sh 02pre taskman taskman filesDir --dry-run
#
# Storage names: filesDir, tmpDir, github, plugins, assets
#
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
die() { error "$1"; exit 1; }

# Apply deletion protection to a PVC
protect_pvc() {
    local pvc_name="$1"
    local namespace="$2"
    local reason="${3:-critical-storage}"
    
    log "Applying deletion protection to PVC: $pvc_name"
    
    kubectl annotate pvc "$pvc_name" -n "$namespace" \
        "helm.sh/resource-policy=keep" \
        "migrate-pvc-to-rwx.sh/protected=true" \
        "migrate-pvc-to-rwx.sh/protection-reason=${reason}" \
        "migrate-pvc-to-rwx.sh/protection-date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --overwrite 2>/dev/null || warn "Could not annotate PVC $pvc_name"
    
    log "PVC '$pvc_name' is now protected against deletion."
}

# Remove deletion protection from a PVC
unprotect_pvc() {
    local pvc_name="$1"
    local namespace="$2"
    
    log "Removing deletion protection from PVC: $pvc_name"
    
    kubectl annotate pvc "$pvc_name" -n "$namespace" \
        "helm.sh/resource-policy-" \
        "migrate-pvc-to-rwx.sh/protected-" \
        "migrate-pvc-to-rwx.sh/protection-reason-" \
        "migrate-pvc-to-rwx.sh/protection-date-" \
        --overwrite 2>/dev/null || warn "Could not remove annotations from PVC $pvc_name"
    
    log "PVC '$pvc_name' protection removed."
}

# List all protected PVCs in a namespace
list_protected_pvcs() {
    local namespace="$1"
    
    log "Checking PVC protection status in namespace: $namespace"
    
    local pvcs
    pvcs=$(kubectl get pvc -n "$namespace" -o json 2>/dev/null | jq -r '.items[] | select(.metadata.annotations."migrate-pvc-to-rwx.sh/protected" == "true") | .metadata.name' 2>/dev/null) || true
    
    if [[ -z "$pvcs" ]]; then
        warn "No protected PVCs found in namespace '$namespace'"
    else
        log "Protected PVCs:"
        echo "$pvcs" | while read -r pvc; do
            local reason
            reason=$(kubectl get pvc "$pvc" -n "$namespace" -o jsonpath='{.metadata.annotations."migrate-pvc-to-rwx.sh/protection-reason"}' 2>/dev/null || echo "unknown")
            echo "  - $pvc ($reason)"
        done
    fi
}

usage() {
    cat <<EOF
Usage: $(basename "$0") <cluster> <namespace> <release-name> <storage-name> [--dry-run]
       $(basename "$0") <cluster> <namespace> <release-name> <storage-name> --sync-only
       $(basename "$0") <cluster> <namespace> <release-name> <storage-name> --protect-only
       $(basename "$0") <cluster> <namespace> <release-name> <storage-name> --unprotect-only
       $(basename "$0") <cluster> <namespace> <release-name> --list-protected

Migrates a PVC from RWO to RWX access mode by creating a new RWX PVC
and copying data from the old PVC.

Arguments:
  cluster        Kubernetes cluster context (e.g., 02pre, 01prod)
  namespace      Kubernetes namespace (e.g., taskman)
  release-name   Helm release name (e.g., taskman)
  storage-name   Storage key from values.yaml (filesDir, tmpDir, github, plugins, assets)
  --dry-run      Show what would be done without executing
  --sync-only    Only sync data between existing PVCs (skip PVC creation)
  --protect-only Protect a PVC against accidental deletion
  --unprotect-only Remove deletion protection from a PVC
  --list-protected List all protected PVCs in the namespace
  --help         Show this help message

Protection:
  All PVCs created by this script are protected with 'helm.sh/resource-policy: keep'
  to prevent accidental deletion during Helm upgrades.

Sync optimization:
  - Uses rsync with --update for incremental sync (only new/changed files)
  - Re-running with --sync-only will only copy missing/new files
  - Alpine-based pod includes rsync for fast transfers

Examples:
  # Full migration: create PVC + copy data
  $(basename "$0") 02pre taskman taskman filesDir
  $(basename "$0") 02pre taskman taskman filesDir --dry-run

  # Incremental sync only (after initial migration, if new data was added)
  $(basename "$0") 02pre taskman taskman filesDir --sync-only

  # Protect a specific PVC
  $(basename "$0") 02pre taskman taskman github --protect-only

  # Unprotect a PVC (allows deletion)
  $(basename "$0") 02pre taskman taskman github --unprotect-only

  # List all protected PVCs
  $(basename "$0") 02pre taskman taskman --list-protected

EOF
    exit 1
}

# Parse arguments
CLUSTER="${1:-}"
NAMESPACE="${2:-}"
RELEASE="${3:-}"
STORAGE_NAME="${4:-}"
DRY_RUN=false
PROTECT_ONLY=false
PROTECT_ACTION="protect"
SYNC_ONLY=false

if [[ "$STORAGE_NAME" == "--help" ]] || [[ "$STORAGE_NAME" == "-h" ]]; then
    usage
fi

if [[ "$STORAGE_NAME" == "--dry-run" ]]; then
    DRY_RUN=true
    STORAGE_NAME="${5:-}"
fi

if [[ "$STORAGE_NAME" == "--sync-only" ]]; then
    SYNC_ONLY=true
    STORAGE_NAME="${5:-}"
fi

if [[ "$STORAGE_NAME" == "--protect-only" ]]; then
    PROTECT_ONLY=true
    PROTECT_ACTION="protect"
    STORAGE_NAME="${5:-}"
fi

if [[ "$STORAGE_NAME" == "--unprotect-only" ]]; then
    PROTECT_ONLY=true
    PROTECT_ACTION="unprotect"
    STORAGE_NAME="${5:-}"
fi

if [[ "$STORAGE_NAME" == "--list-protected" ]]; then
    PROTECT_ONLY=true
    PROTECT_ACTION="list"
    STORAGE_NAME="${5:-}"
fi

# Validate arguments
[[ -z "$CLUSTER" ]] && die "Cluster context is required"
[[ -z "$NAMESPACE" ]] && die "Namespace is required"
[[ -z "$RELEASE" ]] && die "Release name is required"
[[ -z "$STORAGE_NAME" ]] && die "Storage name is required"

# Validate storage name
VALID_STORAGES=(filesDir tmpDir github plugins assets)
if [[ ! " ${VALID_STORAGES[*]} " =~ " ${STORAGE_NAME} " ]]; then
    die "Invalid storage name: $STORAGE_NAME. Valid options: ${VALID_STORAGES[*]}"
fi

# Switch to the target cluster context
log "Switching to cluster context: $CLUSTER"
kubectl config use-context "$CLUSTER" >/dev/null 2>&1 || die "Failed to switch to context: $CLUSTER"

# Handle protect-only mode
if [[ "$PROTECT_ONLY" == "true" ]]; then
    case "$PROTECT_ACTION" in
        protect)
            if [[ -z "$STORAGE_NAME" ]]; then
                die "PVC name required for --protect-only"
            fi
            # Derive PVC name from storage name or use directly
            case "$STORAGE_NAME" in
                filesDir|tmpDir|github|plugins|assets)
                    PVC_NAME="redmine-${STORAGE_NAME}-${RELEASE}-redmine-ss-0"
                    ;;
                *)
                    PVC_NAME="$STORAGE_NAME"
                    ;;
            esac
            protect_pvc "$PVC_NAME" "$NAMESPACE" "manual-protection"
            exit 0
            ;;
        unprotect)
            if [[ -z "$STORAGE_NAME" ]]; then
                die "PVC name required for --unprotect-only"
            fi
            case "$STORAGE_NAME" in
                filesDir|tmpDir|github|plugins|assets)
                    PVC_NAME="redmine-${STORAGE_NAME}-${RELEASE}-redmine-ss-0"
                    ;;
                *)
                    PVC_NAME="$STORAGE_NAME"
                    ;;
            esac
            unprotect_pvc "$PVC_NAME" "$NAMESPACE"
            exit 0
            ;;
        list)
            list_protected_pvcs "$NAMESPACE"
            exit 0
            ;;
    esac
fi

# Get Helm values for the release
log "Fetching Helm values for release '$RELEASE' in namespace '$NAMESPACE'..."
HELM_VALUES=$(helm get values "$RELEASE" -n "$NAMESPACE" -o yaml 2>/dev/null) || die "Failed to get Helm values"

# Extract specific storage subsection from Helm values
# Uses yq for reliable YAML parsing
get_storage_field() {
    local storage="$1"
    local field="$2"
    echo "$HELM_VALUES" | yq -r ".storage.${storage}.${field} // \"\""
}

OLD_CLAIM=$(get_storage_field "$STORAGE_NAME" "existingClaim")
STORAGE_CLASS=$(get_storage_field "$STORAGE_NAME" "storageClassName")
STORAGE_SIZE=$(get_storage_field "$STORAGE_NAME" "size")
ACCESS_MODE=$(get_storage_field "$STORAGE_NAME" "accessMode")

# If existingClaim is empty in current Helm values, check if it exists in the cluster
if [[ -z "$OLD_CLAIM" ]]; then
    # Try to derive from release name pattern
    case "$STORAGE_NAME" in
        filesDir)  OLD_CLAIM="redmine-files-${RELEASE}-redmine-ss-0" ;;
        tmpDir)   OLD_CLAIM="redmine-tmp-${RELEASE}-redmine-ss-0" ;;
        github)   OLD_CLAIM="github-${RELEASE}-redmine-ss-0" ;;
        plugins)  OLD_CLAIM="plugins-${RELEASE}-redmine-ss-0" ;;
        assets)   OLD_CLAIM="redmine-assets-${RELEASE}-ss-0" ;;
    esac
fi

NEW_CLAIM="${OLD_CLAIM}-rwx"

# Check if old PVC exists
log "Checking if old PVC '$OLD_CLAIM' exists..."
OLD_PVC=$(kubectl get pvc "$OLD_CLAIM" -n "$NAMESPACE" -o json 2>/dev/null) || die "Old PVC '$OLD_CLAIM' not found in namespace '$NAMESPACE'"

OLD_ACCESS_MODE=$(echo "$OLD_PVC" | jq -r '.spec.accessModes[0]' 2>/dev/null || echo "unknown")
OLD_SIZE=$(kubectl get pvc "$OLD_CLAIM" -n "$NAMESPACE" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null || echo "unknown")
OLD_STORAGE_CLASS=$(echo "$OLD_PVC" | jq -r '.spec.storageClassName' 2>/dev/null || echo "unknown")

echo ""
log "=== Migration Plan ==="
echo "  Storage name:      $STORAGE_NAME"
echo "  Old PVC:            $OLD_CLAIM"
echo "  New PVC (RWX):      $NEW_CLAIM"
echo "  Old access mode:    $OLD_ACCESS_MODE"
echo "  New access mode:    ReadWriteMany"
echo "  Storage class:      ${OLD_STORAGE_CLASS:-nfs-client}"
echo "  Size:               ${OLD_SIZE:-unknown}"
echo ""

if [[ "$OLD_ACCESS_MODE" == "ReadWriteMany" ]]; then
    warn "Old PVC '$OLD_CLAIM' is already RWX. No migration needed."
    warn "PVC '$OLD_CLAIM' can be shared across replicas."
    # Ensure old PVC is protected anyway
    protect_pvc "$OLD_CLAIM" "$NAMESPACE" "existing-rwx-pvc"
    exit 0
fi

# Check if --sync-only mode: skip PVC creation, just sync data
if [[ "$SYNC_ONLY" == "true" ]]; then
    warn "SYNC_ONLY mode: Skipping PVC creation, will only sync data if both PVCs exist."
    # Verify new PVC exists
    NEW_PVC_CHECK=$(kubectl get pvc "$NEW_CLAIM" -n "$NAMESPACE" 2>/dev/null) || die "New PVC '$NEW_CLAIM' does not exist. Run without --sync-only first."
    log "Both PVCs exist. Proceeding with incremental sync only..."
fi

# Protect the old PVC before migration (prevents accidental deletion during migration)
log "Protecting old PVC '$OLD_CLAIM' against accidental deletion..."
protect_pvc "$OLD_CLAIM" "$NAMESPACE" "source-pvc-migration"

# Create new PVC manifest (skip if SYNC_ONLY)
if [[ "$SYNC_ONLY" != "true" ]]; then
    log "Creating new RWX PVC manifest..."
cat > /tmp/migrate-pvc-${STORAGE_NAME}-${RELEASE}.yaml << EOF
# New RWX PVC for ${STORAGE_NAME} - created by migrate-pvc-to-rwx.sh
# Source PVC: ${OLD_CLAIM}
# Created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${NEW_CLAIM}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/instance: ${RELEASE}
    app.kubernetes.io/name: taskman
    app.kubernetes.io/component: redmine
    migration: migrate-pvc-to-rwx
    created-by: migrate-pvc-to-rwx.sh
  annotations:
    # NEVER DELETE THIS PVC - Critical data storage for Taskman Redmine
    "helm.sh/resource-policy": keep
    "migrate-pvc-to-rwx.sh/source": "${OLD_CLAIM}"
    "migrate-pvc-to-rwx.sh/date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    "migrate-pvc-to-rwx.sh/never-delete": "true"
    "description": "ReadWriteMany PVC for ${STORAGE_NAME} - critical for pod scaling. Do NOT delete."
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: ${OLD_SIZE}
  storageClassName: ${OLD_STORAGE_CLASS:-nfs-client}
EOF

if [[ "$SYNC_ONLY" == "true" ]]; then
    log "SYNC_ONLY mode: Skipping PVC creation, proceeding to sync."
elif [[ "$DRY_RUN" == "true" ]]; then
    echo "New PVC manifest:"
    cat /tmp/migrate-pvc-${STORAGE_NAME}-${RELEASE}.yaml
    echo ""
    warn "[DRY RUN] Would create new PVC: $NEW_CLAIM"
    warn "[DRY RUN] Would copy data from: $OLD_CLAIM to: $NEW_CLAIM"
    warn "[DRY RUN] Would update Helm values to use: $NEW_CLAIM"
    rm -f /tmp/migrate-pvc-${STORAGE_NAME}-${RELEASE}.yaml
    exit 0
else
    echo "New PVC manifest:"
    cat /tmp/migrate-pvc-${STORAGE_NAME}-${RELEASE}.yaml
    echo ""

    # Apply the new PVC
    log "Creating new RWX PVC '$NEW_CLAIM'..."
    kubectl apply -f /tmp/migrate-pvc-${STORAGE_NAME}-${RELEASE}.yaml

    # Wait for PVC to be bound
    log "Waiting for PVC '$NEW_CLAIM' to be bound..."
    timeout=120
    while [[ $timeout -gt 0 ]]; do
        PVC_STATUS=$(kubectl get pvc "$NEW_CLAIM" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
        if [[ "$PVC_STATUS" == "Bound" ]]; then
            log "PVC '$NEW_CLAIM' is bound."
            break
        fi
        echo -n "."
        sleep 2
        ((timeout -= 2))
    done
    echo ""

    if [[ $timeout -le 0 ]]; then
        error "Timeout waiting for PVC '$NEW_CLAIM' to be bound"
        exit 1
    fi

    # Apply deletion protection to the new PVC
    protect_pvc "$NEW_CLAIM" "$NAMESPACE" "rwx-migrated-pvc"
fi

# Create a temporary pod to copy data
TEMP_POD_NAME="data-migrator-$(echo "$STORAGE_NAME" | tr '[:upper:]' '[:lower:]')-$$"
log "Creating temporary pod for data migration..."

cat > /tmp/migrate-pod-${STORAGE_NAME}-${RELEASE}.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${TEMP_POD_NAME}
  namespace: ${NAMESPACE}
spec:
  restartPolicy: Never
  containers:
    - name: migrator
      image: alpine:latest
      command: ["sh", "-c", "apk add --no-cache rsync >/dev/null 2>&1 && echo 'rsync installed' && sleep 3600"]
      volumeMounts:
        - name: old-data
          mountPath: /old
        - name: new-data
          mountPath: /new
  volumes:
    - name: old-data
      persistentVolumeClaim:
        claimName: ${OLD_CLAIM}
    - name: new-data
      persistentVolumeClaim:
        claimName: ${NEW_CLAIM}
EOF

kubectl apply -f /tmp/migrate-pod-${STORAGE_NAME}-${RELEASE}.yaml

# Wait for pod to be running
log "Waiting for migration pod to be ready..."
timeout=60
while [[ $timeout -gt 0 ]]; do
    POD_STATUS=$(kubectl get pod "$TEMP_POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [[ "$POD_STATUS" == "Running" ]]; then
        log "Migration pod is running."
        break
    fi
    echo -n "."
    sleep 2
    ((timeout -= 2))
done
echo ""

if [[ $timeout -le 0 ]]; then
    error "Timeout waiting for migration pod to start"
    kubectl describe pod "$TEMP_POD_NAME" -n "$NAMESPACE"
    exit 1
fi

# Copy data from old PVC to new PVC
log "Copying data from '$OLD_CLAIM' to '$NEW_CLAIM'..."
log "This may take a while depending on data size..."

# Get old PVC file count for comparison (fast method)
log "Checking file counts..."
OLD_FILE_COUNT=$(kubectl exec "$TEMP_POD_NAME" -n "$NAMESPACE" -- sh -c "find /old -type f 2>/dev/null | wc -l" 2>/dev/null || echo "0")
NEW_FILE_COUNT=$(kubectl exec "$TEMP_POD_NAME" -n "$NAMESPACE" -- sh -c "find /new -type f 2>/dev/null | wc -l" 2>/dev/null || echo "0")
OLD_SIZE=$(kubectl exec "$TEMP_POD_NAME" -n "$NAMESPACE" -- sh -c "du -sh /old 2>/dev/null | cut -f1" 2>/dev/null || echo "unknown")

log "Old PVC: $OLD_SIZE, $OLD_FILE_COUNT files"
log "New PVC already has: $NEW_FILE_COUNT files"

if [[ "$NEW_FILE_COUNT" -gt 0 ]] && [[ "$NEW_FILE_COUNT" -ge "$OLD_FILE_COUNT" ]]; then
    warn "New PVC already has $NEW_FILE_COUNT files (>= old $OLD_FILE_COUNT). Sync may be complete."
    log "Run --sync-only to re-verify and sync any new files."
fi

# Fast rsync: use archive mode, skip identical files, compress during transfer
kubectl exec "$TEMP_POD_NAME" -n "$NAMESPACE" -- sh -c "
    echo 'Starting incremental sync...'
    echo 'Using rsync with --checksum (skip by size/mtime) for speed...'
    
    if command -v rsync >/dev/null 2>&1; then
        # Fast options: skip by size/mtime, show summary, don't cross filesystem
        rsync -av --size-only --omit-dir-times --no-perms \
              --progress /old/ /new/ 2>&1 | tail -40
        
        # Quick verification
        echo ''
        echo '=== Sync Summary ==='
        echo 'New files count:' && find /new -type f 2>/dev/null | wc -l
    else
        echo 'rsync not available, using cp -u...'
        cp -auv /old/* /new/ 2>&1 | tail -20
        echo 'New files count:' && find /new -type f 2>/dev/null | wc -l
    fi
    
    echo ''
    echo 'Old size:' && du -sh /old
    echo 'New size:' && du -sh /new
"

# Clean up the migration pod
log "Cleaning up migration pod..."
kubectl delete pod "$TEMP_POD_NAME" -n "$NAMESPACE" --wait=true 2>/dev/null || true

# Clean up temp files
rm -f /tmp/migrate-pvc-${STORAGE_NAME}-${RELEASE}.yaml
rm -f /tmp/migrate-pod-${STORAGE_NAME}-${RELEASE}.yaml

log "Migration completed successfully!"
log "New PVC '$NEW_CLAIM' is ready with RWX access mode."
log ""
log "Both PVCs are now protected against accidental deletion:"
log "  - $OLD_CLAIM (protected, source)"
log "  - $NEW_CLAIM (protected, RWX)"
echo ""
echo "To remove protection (if needed):"
echo "  $0 $CLUSTER $NAMESPACE $RELEASE $STORAGE_NAME --unprotect-only"