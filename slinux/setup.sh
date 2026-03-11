#!/bin/bash
# =============================================================
#  setupx-linux  —  Master Setup Script
#  Runs all numbered scripts in order.
#  Usage:
#    bash setup.sh               # run all scripts
#    bash setup.sh 3 7           # run only scripts 03, 04, 05, 06, 07
#    bash setup.sh --skip 1 9    # skip scripts 01 and 09
#    bash setup.sh --skip 11     # skip Cloudflare tunnel setup
#    bash setup.sh 12 12         # run only the test+DNS script
# =============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/setup-$(date +%Y%m%d-%H%M%S).log"

# --- Colour helpers ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()   { echo -e "${CYAN}[INFO]${RESET}  $*" | tee -a "$LOG_FILE"; }
ok()    { echo -e "${GREEN}[OK]${RESET}    $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR]${RESET} $*" | tee -a "$LOG_FILE"; }
die()   { error "$*"; exit 1; }

# --- Parse arguments ---
SKIP_NUMS=()
RUN_RANGE=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip)
      shift
      while [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; do
        SKIP_NUMS+=("$1"); shift
      done ;;
    [0-9]*)
      RUN_RANGE+=("$1"); shift ;;
    *) die "Unknown argument: $1" ;;
  esac
done

should_run() {
  local num=$1
  # Check skip list
  for s in "${SKIP_NUMS[@]:-}"; do
    [[ "$num" == "$s" ]] && return 1
  done
  # Check run range (if specified)
  if [[ ${#RUN_RANGE[@]} -gt 0 ]]; then
    local start=${RUN_RANGE[0]}
    local end=${RUN_RANGE[${#RUN_RANGE[@]}-1]}
    [[ "$num" -ge "$start" && "$num" -le "$end" ]] && return 0
    return 1
  fi
  return 0
}

# --- Header ---
echo -e "${BOLD}"
echo "============================================"
echo "   setupx-linux  —  Master Setup Script"
echo "============================================"
echo -e "${RESET}"
log "Log file: $LOG_FILE"
echo ""

# --- Collect all numbered scripts ---
mapfile -t SCRIPTS < <(ls "$SCRIPT_DIR"/[0-9][0-9]-*.sh 2>/dev/null | sort)

if [[ ${#SCRIPTS[@]} -eq 0 ]]; then
  die "No numbered scripts found in $SCRIPT_DIR"
fi

TOTAL=${#SCRIPTS[@]}
PASSED=0
FAILED=0
SKIPPED=0
FAILED_SCRIPTS=()

# --- Run each script ---
for script in "${SCRIPTS[@]}"; do
  name=$(basename "$script")
  num=$(echo "$name" | grep -oP '^\d+')

  if ! should_run "$((10#$num))"; then
    warn "Skipping [$name]"
    ((SKIPPED++)) || true
    continue
  fi

  echo -e "${BOLD}--- [$name] ---${RESET}" | tee -a "$LOG_FILE"
  log "Starting: $name"

  if bash "$script" 2>&1 | tee -a "$LOG_FILE"; then
    ok "Completed: $name"
    ((PASSED++)) || true
  else
    EXIT_CODE=$?
    error "Failed: $name (exit $EXIT_CODE)"
    FAILED_SCRIPTS+=("$name")
    ((FAILED++)) || true

    echo ""
    warn "Script [$name] failed. Choose:"
    echo "  [c] Continue to next script"
    echo "  [r] Retry this script"
    echo "  [a] Abort"
    read -rp "  > " choice 2>/dev/null || choice="c"
    case "$choice" in
      r)
        log "Retrying: $name"
        if bash "$script" 2>&1 | tee -a "$LOG_FILE"; then
          ok "Retry succeeded: $name"
          ((FAILED--)) || true
          FAILED_SCRIPTS=("${FAILED_SCRIPTS[@]/$name}")
          ((PASSED++)) || true
        else
          error "Retry failed: $name"
        fi ;;
      a) die "Aborted by user after failure in [$name]" ;;
      *) warn "Continuing after failure in [$name]" ;;
    esac
  fi
  echo ""
done

# --- Summary ---
echo -e "${BOLD}"
echo "============================================"
echo "   Setup Summary"
echo "============================================"
echo -e "${RESET}"
echo -e "  Total scripts : $TOTAL"
echo -e "  ${GREEN}Passed${RESET}        : $PASSED"
echo -e "  ${YELLOW}Skipped${RESET}       : $SKIPPED"
echo -e "  ${RED}Failed${RESET}        : $FAILED"
echo ""

if [[ $FAILED -gt 0 ]]; then
  error "Failed scripts:"
  for f in "${FAILED_SCRIPTS[@]}"; do
    [[ -n "$f" ]] && echo "    - $f"
  done
  echo ""
  warn "Review log: $LOG_FILE"
  exit 1
else
  ok "All scripts completed successfully!"
  log "Log saved to: $LOG_FILE"
fi
