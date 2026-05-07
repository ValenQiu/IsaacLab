#!/usr/bin/env bash
# List or terminate Isaac Sim / play.py processes (fixes duplicate Kit KVDB lock).
# Usage:
#   bash fuyao/kill_isaac_play_processes.sh           # list only
#   bash fuyao/kill_isaac_play_processes.sh --kill    # terminate matches
#   bash fuyao/kill_isaac_play_processes.sh --kill --yes   # no confirm
set -euo pipefail

KILL=false
YES=false
for arg in "$@"; do
  case "$arg" in
    --kill) KILL=true ;;
    --yes) YES=true ;;
    -h|--help)
      sed -n '1,12p' "$0"
      exit 0
      ;;
  esac
done

echo "=== Processes matching play.py (whole_body_tracking / rsl_rl) ==="
PLAY_PIDS=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  pid="${line%% *}"
  PLAY_PIDS+=("$pid")
  echo "  $line"
done < <(pgrep -af 'python.*play\.py' 2>/dev/null || true)

echo ""
echo "=== Isaac Sim Kit python (second instance / KVDB lock) ==="
KIT_PIDS=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  pid="${line%% *}"
  KIT_PIDS+=("$pid")
  echo "  $line"
done < <(pgrep -af 'kit/python/bin/python' 2>/dev/null || true)

if [[ "$KILL" != true ]]; then
  echo ""
  echo "[INFO] List only. Re-run with --kill to send SIGTERM (then SIGKILL if needed)."
  exit 0
fi

# Merge unique PIDs
declare -A seen=()
UNIQUE=()
for pid in "${PLAY_PIDS[@]}" "${KIT_PIDS[@]}"; do
  pid="${pid// /}"
  [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]] && continue
  if [[ -z "${seen[$pid]:-}" ]]; then
    seen[$pid]=1
    UNIQUE+=("$pid")
  fi
done

if [[ ${#UNIQUE[@]} -eq 0 ]]; then
  echo "[INFO] No matching PIDs to kill."
  exit 0
fi

if [[ "$YES" != true ]]; then
  echo ""
  read -r -p "Kill PIDs: ${UNIQUE[*]} ? [y/N] " ans
  [[ "${ans:-}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

for pid in "${UNIQUE[@]}"; do
  if kill -0 "$pid" 2>/dev/null; then
    echo "[INFO] SIGTERM $pid"
    kill -TERM "$pid" 2>/dev/null || true
  fi
done

sleep 2
for pid in "${UNIQUE[@]}"; do
  if kill -0 "$pid" 2>/dev/null; then
    echo "[WARN] SIGKILL $pid (still alive)"
    kill -KILL "$pid" 2>/dev/null || true
  fi
done

echo "[INFO] Done. Verify: nvidia-smi | ps aux | grep play"
