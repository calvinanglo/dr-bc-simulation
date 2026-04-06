#!/bin/bash
# rto-timer.sh
# tracks and logs RTO measurement per phase during a DR test
# usage: ./rto-timer.sh [start|phase|stop]
#   start  — begin RTO tracking, records start time
#   phase  — log a phase completion checkpoint
#   stop   — end tracking, print summary

set -euo pipefail

TIMER_FILE="/tmp/rto-timer.state"
LOG_FILE="/tmp/rto-timer-$(date +%Y%m%d).log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

case "${1:-help}" in
  start)
    START=$(date +%s)
    echo "start=$START" > "$TIMER_FILE"
    echo "phases=" >> "$TIMER_FILE"
    log "RTO timer started"
    ;;

  phase)
    if [[ ! -f "$TIMER_FILE" ]]; then
      echo "Error: timer not started. Run: $0 start"
      exit 1
    fi
    PHASE_NAME="${2:-unnamed}"
    NOW=$(date +%s)
    source "$TIMER_FILE"
    ELAPSED=$(( NOW - start ))
    ELAPSED_MIN=$(( ELAPSED / 60 ))
    log "PHASE COMPLETE: $PHASE_NAME at T+${ELAPSED_MIN}m (${ELAPSED}s)"
    echo "$PHASE_NAME=$ELAPSED" >> "$TIMER_FILE"
    ;;

  stop)
    if [[ ! -f "$TIMER_FILE" ]]; then
      echo "Error: timer not started. Run: $0 start"
      exit 1
    fi
    NOW=$(date +%s)
    source "$TIMER_FILE"
    TOTAL=$(( NOW - start ))
    TOTAL_MIN=$(( TOTAL / 60 ))
    TOTAL_HR=$(( TOTAL_MIN / 60 ))
    REMAINING_MIN=$(( TOTAL_MIN % 60 ))

    log ""
    log "===== RTO SUMMARY ====="
    log "Total elapsed: ${TOTAL_HR}h ${REMAINING_MIN}m (${TOTAL}s)"
    log ""

    # print phase breakdown
    while IFS='=' read -r key val; do
      if [[ "$key" != "start" && "$key" != "phases" && -n "$val" ]]; then
        PHASE_MIN=$(( val / 60 ))
        log "  $key: T+${PHASE_MIN}m"
      fi
    done < "$TIMER_FILE"

    log ""
    log "Results saved to: $LOG_FILE"
    rm -f "$TIMER_FILE"
    ;;

  *)
    echo "Usage: $0 [start|phase <name>|stop]"
    echo "  start         — begin RTO tracking"
    echo "  phase <name>  — log a phase checkpoint"
    echo "  stop          — end tracking, print summary"
    ;;
esac
