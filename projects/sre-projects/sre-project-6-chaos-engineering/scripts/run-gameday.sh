#!/bin/bash
##############################################################################
# Automated Game Day Runner
#
# Runs a full Game Day sequence: steady-state → chaos → verify → repeat.
# The Game Master controls the pace; responders must detect and resolve.
#
# Usage:
#   ./run-gameday.sh [NAMESPACE]
#
# Example:
#   ./run-gameday.sh sre-demo
##############################################################################

set -euo pipefail

NAMESPACE="${1:-sre-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GAMEDAY_LOG="/tmp/gameday-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "$1" | tee -a "$GAMEDAY_LOG"; }

log "╔════════════════════════════════════════════════╗"
log "║          SRE CHAOS GAME DAY                    ║"
log "╠════════════════════════════════════════════════╣"
log "║  Namespace: $NAMESPACE"
log "║  Started:   $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
log "║  Log file:  $GAMEDAY_LOG"
log "╚════════════════════════════════════════════════╝"
log ""

# ── Pre-flight ─────────────────────────────────────────────────────────
log "${BLUE}[PRE-FLIGHT]${NC} Checking cluster..."
if ! kubectl get nodes &>/dev/null; then
    log "${RED}[ERROR]${NC} Cannot access cluster"
    exit 1
fi
log "${GREEN}[OK]${NC} Cluster accessible"
log ""

# ── Function: Run steady-state check ──────────────────────────────────
run_steady_state() {
    local phase="$1"
    log "${BLUE}[STEADY-STATE: $phase]${NC} Running validation..."

    kubectl delete job steady-state-check -n "$NAMESPACE" --ignore-not-found 2>/dev/null
    kubectl apply -f "$PROJECT_DIR/steady-state/steady-state-checks.yaml" 2>/dev/null

    sleep 5
    kubectl wait --for=condition=complete job/steady-state-check -n "$NAMESPACE" --timeout=120s 2>/dev/null || true
    kubectl logs job/steady-state-check -n "$NAMESPACE" 2>/dev/null | tee -a "$GAMEDAY_LOG"
    log ""
}

# ── Function: Run experiment ──────────────────────────────────────────
run_experiment() {
    local name="$1"
    local file="$2"
    local duration="$3"

    log "╔════════════════════════════════════════════════╗"
    log "║  ROUND: $name"
    log "║  Time:  $(date -u '+%H:%M:%S UTC')"
    log "╚════════════════════════════════════════════════╝"
    log ""
    log "${YELLOW}[CHAOS]${NC} Injecting: $name"
    log "${YELLOW}[CHAOS]${NC} Duration: ${duration}s"
    log ""
    log "${RED}>>> RESPONDERS: An incident has been injected! <<<${NC}"
    log "${RED}>>> Use your monitoring tools and runbooks to respond. <<<${NC}"
    log ""

    INJECT_TIME=$(date +%s)

    # Apply the manual job
    kubectl delete job "${name}-manual" -n "$NAMESPACE" --ignore-not-found 2>/dev/null
    kubectl apply -f "$file" 2>/dev/null || log "${YELLOW}[WARN]${NC} Could not apply Litmus experiment, using manual job"

    # Wait for experiment duration
    log "${BLUE}[INFO]${NC} Experiment running for ${duration}s..."
    local elapsed=0
    while [ $elapsed -lt "$duration" ]; do
        sleep 10
        elapsed=$((elapsed + 10))
        local remaining=$((duration - elapsed))
        log "  [$(date -u '+%H:%M:%S')] Elapsed: ${elapsed}s | Remaining: ${remaining}s"
    done

    log ""
    log "${GREEN}[CHAOS ENDED]${NC} Experiment '$name' complete"
    log ""

    # Prompt for response (if interactive)
    if [ -t 0 ]; then
        log "Press ENTER when responders have resolved the issue..."
        read -r

        RESOLVE_TIME=$(date +%s)
        RESPONSE_SECS=$((RESOLVE_TIME - INJECT_TIME))
        RESPONSE_MINS=$((RESPONSE_SECS / 60))
        RESPONSE_REM=$((RESPONSE_SECS % 60))
        log "${BLUE}[METRICS]${NC} Response time: ${RESPONSE_MINS}m ${RESPONSE_REM}s"
    else
        log "${BLUE}[INFO]${NC} Non-interactive mode, waiting 30s for recovery..."
        sleep 30
    fi

    log ""
}

# ═══════════════════════════════════════════════════════════════════════
# GAME DAY EXECUTION
# ═══════════════════════════════════════════════════════════════════════

# Phase 1: Initial steady state
run_steady_state "BASELINE"

log "═══ GAME DAY STARTING IN 10 SECONDS ═══"
log "Open your monitoring dashboards NOW:"
log "  Prometheus: http://localhost:9090"
log "  Grafana:    http://localhost:3000"
log ""
sleep 10

# Phase 2: Round 1 — Pod Delete
run_experiment "pod-delete" \
  "$PROJECT_DIR/experiments/pod-level/pod-delete.yaml" 60

log "${BLUE}[RECOVERY]${NC} 60s recovery window..."
sleep 60
run_steady_state "AFTER ROUND 1"

# Phase 3: Round 2 — CPU Hog
run_experiment "pod-cpu-hog" \
  "$PROJECT_DIR/experiments/pod-level/pod-cpu-hog.yaml" 120

log "${BLUE}[RECOVERY]${NC} 60s recovery window..."
sleep 60
run_steady_state "AFTER ROUND 2"

# Phase 4: Round 3 — Container Kill
run_experiment "container-kill" \
  "$PROJECT_DIR/experiments/application/app-kill.yaml" 60

log "${BLUE}[RECOVERY]${NC} 60s recovery window..."
sleep 60
run_steady_state "AFTER ROUND 3"

# ── Final Summary ──────────────────────────────────────────────────────
log ""
log "╔════════════════════════════════════════════════╗"
log "║          GAME DAY COMPLETE                     ║"
log "╠════════════════════════════════════════════════╣"
log "║  Ended: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
log "║  Log:   $GAMEDAY_LOG"
log "║                                                ║"
log "║  Next steps:                                   ║"
log "║  1. Review the log file                        ║"
log "║  2. Score the resilience scorecard              ║"
log "║  3. File tickets for improvements              ║"
log "║  4. Update runbooks with findings              ║"
log "║  5. Schedule the next Game Day                 ║"
log "╚════════════════════════════════════════════════╝"
