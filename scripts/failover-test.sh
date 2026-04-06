#!/bin/bash
# failover-test.sh
# orchestrates a DR failover test by simulating primary site failure
# runs through the DR runbook phases and logs timing at each checkpoint
# usage: ./failover-test.sh [scenario]
#   scenario 1 = network failure only
#   scenario 2 = database server failure only
#   scenario 3 = full site loss (default)

set -euo pipefail

SCENARIO="${1:-3}"
LOG_FILE="/var/log/dr-test-$(date +%Y%m%d-%H%M%S).log"
SITE_A_WEB="10.10.20.10"
SITE_A_DB="10.10.20.20"
SITE_B_WEB="10.10.20.110"
SITE_B_DB="10.10.20.120"
SITE_B_FW="10.10.20.101"
NAS="10.10.20.50"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

check_host() {
  ping -c 1 -W 2 "$1" > /dev/null 2>&1
}

START_TIME=$(date +%s)

log "===== DR FAILOVER TEST - SCENARIO $SCENARIO ====="
log "Test start: $(date)"
log ""

# pre-flight: verify site-b is reachable and backups are valid
log "--- PRE-FLIGHT CHECKS ---"

if check_host "$SITE_B_FW"; then
  log "PASS: Site-B firewall reachable at $SITE_B_FW"
else
  log "FAIL: Site-B firewall unreachable at $SITE_B_FW - aborting"
  exit 1
fi

if check_host "$NAS"; then
  log "PASS: NAS reachable at $NAS"
else
  log "FAIL: NAS unreachable at $NAS - aborting"
  exit 1
fi

log "Running backup validation..."
if bash "$(dirname "$0")/backup-validate.sh"; then
  log "PASS: Backup validation passed"
else
  log "FAIL: Backup validation failed - fix before proceeding"
  exit 1
fi

log ""
log "--- PHASE 1: SIMULATE PRIMARY SITE FAILURE ---"
PHASE1_START=$(date +%s)

case $SCENARIO in
  1)
    log "Scenario 1: network failure only"
    log "Action: shut down primary site uplink (manual step)"
    log "Waiting for operator to confirm primary network is down..."
    read -p "Press enter once primary network is disabled: "
    ;;
  2)
    log "Scenario 2: database server failure"
    log "Action: shut down primary DB VM (manual step on Proxmox)"
    log "Waiting for operator to confirm DB VM is stopped..."
    read -p "Press enter once DB VM is stopped: "
    ;;
  3)
    log "Scenario 3: full primary site loss"
    log "Action: shut down all primary site VMs (manual step on Proxmox)"
    log "Waiting for operator to confirm all site-a VMs are stopped..."
    read -p "Press enter once all site-a VMs are stopped: "
    ;;
esac

log ""
log "--- PHASE 2: NETWORK CUTOVER ---"

log "Verifying site-b firewall WAN connectivity..."
if ssh admin@"$SITE_B_FW" "ping -c 2 8.8.8.8" > /dev/null 2>&1; then
  log "PASS: Site-B WAN is active"
else
  log "FAIL: Site-B WAN is down - contact ISP"
fi

log "DNS failover: update A records to point to site-b IPs"
log "  web.internal -> $SITE_B_WEB"
log "  db.internal  -> $SITE_B_DB"
log "(manual step - update /etc/bind/zones/ and reload bind9)"
read -p "Press enter once DNS is updated: "

PHASE1_END=$(date +%s)
PHASE1_DURATION=$(( PHASE1_END - PHASE1_START ))
log "Phase 1+2 complete in ${PHASE1_DURATION}s (target: 1800s / 30min)"
log ""

# phase 3: database restore (scenarios 2 and 3 only)
if [[ "$SCENARIO" != "1" ]]; then
  log "--- PHASE 3: DATABASE RESTORE ---"
  PHASE3_START=$(date +%s)

  log "Checking for latest backup on NAS..."
  LATEST_BACKUP=$(ssh backup-user@"$NAS" "ls -t /mnt/nas-backup/postgresql/full/*.pgdump 2>/dev/null | head -1")
  if [[ -n "$LATEST_BACKUP" ]]; then
    log "PASS: Found backup: $LATEST_BACKUP"
  else
    log "FAIL: No backup found on NAS"
    exit 1
  fi

  log "Starting pg_restore on site-b DB ($SITE_B_DB)..."
  log "(manual step - follow runbook phase 2 for pg_restore + WAL replay)"
  read -p "Press enter once database restore is complete: "

  PHASE3_END=$(date +%s)
  PHASE3_DURATION=$(( PHASE3_END - PHASE3_START ))
  log "Phase 3 complete in ${PHASE3_DURATION}s (target: 14400s / 4hr)"
fi

log ""
log "--- PHASE 4: SERVICE VALIDATION ---"

log "Testing web tier..."
if check_host "$SITE_B_WEB"; then
  log "PASS: Web server reachable at $SITE_B_WEB"
else
  log "FAIL: Web server unreachable at $SITE_B_WEB"
fi

if [[ "$SCENARIO" != "1" ]]; then
  log "Testing database..."
  if ssh "$SITE_B_DB" "sudo -u postgres psql -c 'SELECT 1;'" > /dev/null 2>&1; then
    log "PASS: Database responding on $SITE_B_DB"
  else
    log "FAIL: Database not responding on $SITE_B_DB"
  fi
fi

END_TIME=$(date +%s)
TOTAL_DURATION=$(( END_TIME - START_TIME ))
TOTAL_MINUTES=$(( TOTAL_DURATION / 60 ))

log ""
log "===== TEST COMPLETE ====="
log "Total duration: ${TOTAL_MINUTES} minutes (${TOTAL_DURATION}s)"
log "Results saved to: $LOG_FILE"
log ""
log "Next steps:"
log "  1. Fill in test results at test-results/dr-test-$(date +%Y-%m-%d).md"
log "  2. Notify stakeholders per bc-communication-plan.md"
log "  3. Schedule post-incident review within 5 business days"
