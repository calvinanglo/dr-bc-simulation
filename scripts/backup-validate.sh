#!/bin/bash
# backup-validate.sh
# runs monthly backup validation checks - verifies files exist, checksums are good,
# and the pg_dump is actually restorable
# logs results to /var/log/backup-validate.log and exits non-zero if anything fails

set -euo pipefail

LOG_FILE="/var/log/backup-validate.log"
NAS_BACKUP="/mnt/nas-backup"
PG_FULL_DIR="${NAS_BACKUP}/postgresql/full"
PG_WAL_DIR="${NAS_BACKUP}/postgresql/wal"
MAX_BACKUP_AGE_HOURS=25
MAX_WAL_AGE_MINUTES=15
RESULTS_FILE="/tmp/backup-validate-$(date +%Y%m%d-%H%M%S).txt"

PASS=0
FAIL=0

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

pass() {
  log "PASS: $*"
  echo "PASS: $*" >> "$RESULTS_FILE"
  ((PASS++))
}

fail() {
  log "FAIL: $*"
  echo "FAIL: $*" >> "$RESULTS_FILE"
  ((FAIL++))
}

log "===== backup validation started ====="
echo "Backup Validation Run: $(date)" > "$RESULTS_FILE"

# check 1: nas mount is actually mounted
if mountpoint -q "${NAS_BACKUP}"; then
  pass "NAS backup mount is active at ${NAS_BACKUP}"
else
  fail "NAS backup mount is NOT mounted at ${NAS_BACKUP} - backups may be going to local disk"
  log "CRITICAL: NAS not mounted. Aborting remaining checks."
  exit 1
fi

# check 2: latest full backup exists and is recent
LATEST_FULL=$(ls -t "${PG_FULL_DIR}"/*.pgdump 2>/dev/null | head -1)
if [[ -z "$LATEST_FULL" ]]; then
  fail "No .pgdump files found in ${PG_FULL_DIR}"
else
  BACKUP_AGE_HOURS=$(( ( $(date +%s) - $(stat -c %Y "$LATEST_FULL") ) / 3600 ))
  if [[ $BACKUP_AGE_HOURS -le $MAX_BACKUP_AGE_HOURS ]]; then
    pass "Latest full backup is ${BACKUP_AGE_HOURS}h old: $(basename "$LATEST_FULL")"
  else
    fail "Latest full backup is ${BACKUP_AGE_HOURS}h old (max allowed: ${MAX_BACKUP_AGE_HOURS}h): $(basename "$LATEST_FULL")"
  fi
fi

# check 3: latest WAL archive is recent enough for RPO
LATEST_WAL=$(ls -t "${PG_WAL_DIR}"/ 2>/dev/null | head -1)
if [[ -z "$LATEST_WAL" ]]; then
  fail "No WAL archives found in ${PG_WAL_DIR}"
else
  WAL_AGE_MIN=$(( ( $(date +%s) - $(stat -c %Y "${PG_WAL_DIR}/${LATEST_WAL}") ) / 60 ))
  if [[ $WAL_AGE_MIN -le $MAX_WAL_AGE_MINUTES ]]; then
    pass "Latest WAL archive is ${WAL_AGE_MIN} minutes old (RPO within target)"
  else
    fail "Latest WAL archive is ${WAL_AGE_MIN} minutes old (exceeds ${MAX_WAL_AGE_MINUTES} min RPO target)"
  fi
fi

# check 4: checksum verification on latest full backup
if [[ -n "${LATEST_FULL:-}" ]]; then
  CHECKSUM_FILE="${LATEST_FULL}.sha256"
  if [[ -f "$CHECKSUM_FILE" ]]; then
    if sha256sum --check "$CHECKSUM_FILE" --quiet 2>/dev/null; then
      pass "Checksum verified for $(basename "$LATEST_FULL")"
    else
      fail "Checksum MISMATCH for $(basename "$LATEST_FULL") - backup may be corrupt"
    fi
  else
    fail "No checksum file found for $(basename "$LATEST_FULL") - cannot verify integrity"
  fi
fi

# check 5: pg_restore --list to verify the dump file is valid (doesn't do a full restore)
if [[ -n "${LATEST_FULL:-}" ]]; then
  OBJECT_COUNT=$(pg_restore --list "$LATEST_FULL" 2>/dev/null | wc -l)
  if [[ $OBJECT_COUNT -gt 0 ]]; then
    pass "pg_restore --list succeeded: ${OBJECT_COUNT} objects in backup"
  else
    fail "pg_restore --list returned 0 objects - backup file may be empty or corrupt"
  fi
fi

# check 6: disk space on NAS - make sure we have room for next backup cycle
NAS_USAGE=$(df -h "${NAS_BACKUP}" | awk 'NR==2 {print $5}' | tr -d '%')
if [[ $NAS_USAGE -lt 80 ]]; then
  pass "NAS disk usage is ${NAS_USAGE}% (below 80% threshold)"
elif [[ $NAS_USAGE -lt 90 ]]; then
  fail "NAS disk usage is ${NAS_USAGE}% - getting close, consider cleanup"
else
  fail "NAS disk usage is ${NAS_USAGE}% - CRITICAL, backup may fail at next run"
fi

# summary
log "===== validation complete: ${PASS} passed, ${FAIL} failed ====="
echo "" >> "$RESULTS_FILE"
echo "Summary: ${PASS} passed, ${FAIL} failed" >> "$RESULTS_FILE"
echo "Results saved to: $RESULTS_FILE"

if [[ $FAIL -gt 0 ]]; then
  log "Validation FAILED - review $RESULTS_FILE and fix issues before next DR test"
  exit 1
else
  log "Validation PASSED - backup health looks good"
  exit 0
fi
