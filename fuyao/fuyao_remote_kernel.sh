#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Load optional local config: fuyao/.env
if [[ -f fuyao/.env ]]; then
  # shellcheck disable=SC1091
  source fuyao/.env
fi

# Fallback: if WANDB_API_KEY not set in fuyao/.env, try local key file.
if [[ -z "${WANDB_API_KEY:-}" && -f "$HOME/.wandb_api_key" ]]; then
  WANDB_API_KEY="$(head -n 1 "$HOME/.wandb_api_key" | tr -d '\r' | xargs)"
fi

DEFAULT_IMAGE="infra-registry-vpc.cn-wulanchabu.cr.aliyuncs.com/data-infra/fuyao:isaaclab-260404-0534"
DEFAULT_PROJECT="${DEFAULT_PROJECT:-rc-wbc}"
DEFAULT_SITE="${DEFAULT_SITE:-fuyao_sh_n2}"
DEFAULT_QUEUE="${DEFAULT_QUEUE:-rc-wbc-4090-share}"
DEFAULT_EXPERIMENT="${DEFAULT_EXPERIMENT:-}"
DEFAULT_GPUS="${DEFAULT_GPUS:-1}"
DEFAULT_NODES="${DEFAULT_NODES:-1}"
DEFAULT_LABEL="${DEFAULT_LABEL:-test}"
DEFAULT_VOLUME="${DEFAULT_VOLUME:-rc-wbc}"
# rc-wbc-4090-share is a SHAREDGPU queue: --cpus/--gibs are ignored; resources are
# allocated proportionally to --gpu-slice. Use 1of1 for the full 4090 (24GB VRAM).
# Slice options: 1of8 (~3GB) | 1of4 (~6GB) | 1of2 (~12GB) | 1of1 (full 24GB)
DEFAULT_GPU_SLICE="${DEFAULT_GPU_SLICE:-1of1}"

image="$DEFAULT_IMAGE"
project="$DEFAULT_PROJECT"
site="$DEFAULT_SITE"
queue="$DEFAULT_QUEUE"
experiment="$DEFAULT_EXPERIMENT"
gpus="$DEFAULT_GPUS"
nodes="$DEFAULT_NODES"
label="$DEFAULT_LABEL"
volume="$DEFAULT_VOLUME"
gpu_slice="$DEFAULT_GPU_SLICE"

show_help() {
  cat <<EOF
Usage: $0 [options]

Options:
  --image <image>
  --project <project>
  --site <site>
  --queue <queue>
  --experiment <exp>       (required)
  --gpus <num>             GPUs per node (default: $DEFAULT_GPUS)
  --nodes <num>
  --label <label>
  --volume <volume>        (required)
  --gpu-slice <slice>      GPU slice for shared queue: 1of8|1of4|1of2|1of1 (default: $DEFAULT_GPU_SLICE)
  -h, --help
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) image="$2"; shift 2 ;;
    --project) project="$2"; shift 2 ;;
    --site) site="$2"; shift 2 ;;
    --queue) queue="$2"; shift 2 ;;
    --experiment) experiment="$2"; shift 2 ;;
    --gpus) gpus="$2"; shift 2 ;;
    --nodes) nodes="$2"; shift 2 ;;
    --label) label="$2"; shift 2 ;;
    --volume) volume="$2"; shift 2 ;;
    --gpu-slice) gpu_slice="$2"; shift 2 ;;
    -h|--help) show_help ;;
    *) echo "[ERROR] Unknown arg: $1"; exit 1 ;;
  esac
done

# --- Validate required parameters ---
errors=()
if [[ -z "$experiment" ]]; then errors+=("--experiment is required"); fi
if [[ -z "$site" ]]; then errors+=("--site is required"); fi
if [[ -z "$volume" ]]; then errors+=("--volume is required"); fi

if [[ "${#errors[@]}" -gt 0 ]]; then
  for e in "${errors[@]}"; do echo "[ERROR] $e"; done
  exit 1
fi

if [[ ! "$gpu_slice" =~ ^1of(1|2|4|8)$ ]]; then
  echo "[ERROR] --gpu-slice must be one of: 1of1, 1of2, 1of4, 1of8 (got: $gpu_slice)"
  exit 1
fi

# --- Deployment info banner ---
echo "========================================================"
echo "[INFO] Fuyao Remote Kernel Deployment"
echo "========================================================"
echo "  Image:        $image"
echo "  Project:      $project"
echo "  Site:         $site"
echo "  Queue:        $queue"
echo "  Experiment:   $experiment"
echo "  Volume:       $volume"
echo "  GPUs/node:    $gpus  |  Nodes: $nodes  |  Slice: $gpu_slice"
echo "  Label:        $label"
echo "  Bootstrap:    /opt/data-infra/remote_kernel_bootstrap.sh"
echo "========================================================"

stamp=$(date +%Y%m%d%H%M%S%N)
tmp_dir="/tmp/fuyao_deploy_${stamp}"

echo "[INFO] Create temp dir: $tmp_dir"
rm -rf "$tmp_dir"
mkdir -p "$tmp_dir"

echo "[INFO] Sync project with .gitignore filtering"
rsync -a --filter=':- .gitignore' . "$tmp_dir/"

# Optional secret injection (from local fuyao/.env):
#   WANDB_API_KEY=xxxx
# We only write into the ephemeral deploy snapshot, never into git workspace.
if [[ -n "${WANDB_API_KEY:-}" ]]; then
  echo "[INFO] Inject WANDB_API_KEY into ephemeral deploy snapshot"
  mkdir -p "$tmp_dir/.remote_secrets"
  printf '%s\n' "$WANDB_API_KEY" > "$tmp_dir/.remote_secrets/wandb_api_key"
  chmod 600 "$tmp_dir/.remote_secrets/wandb_api_key"
fi

cd "$tmp_dir"
deploy_status=0
fuyao deploy \
  --remote-kernel \
  --project="$project" \
  --experiment="$experiment" \
  --label="$label" \
  --docker-image="$image" \
  --site="$site" \
  --queue="$queue" \
  --volume="$volume" \
  --nodes="$nodes" \
  --gpus-per-node="$gpus" \
  --gpu-type=shared \
  --gpu-slice="$gpu_slice" \
  --ignore-artifact-size || deploy_status=$?

echo "[INFO] Cleanup temp dir: $tmp_dir"
rm -rf "$tmp_dir"

if [[ $deploy_status -eq 0 ]]; then
  echo ""
  echo "========================================================"
  echo "[INFO] Deploy succeeded. Verify bootstrap after ~60s:"
  echo ""
  echo "  # Check bootstrap log:"
  echo "  tail -n 80 /opt/data-infra/remote-kernel-bootstrap.log"
  echo ""
  echo "  # Verify core imports:"
  echo "  /isaac-sim/python.sh -c \"import isaaclab, toml, requests, torch; print('core ok')\""
  echo "  /isaac-sim/python.sh -c \"import whole_body_tracking; print('wbt ok')\""
  echo ""
  echo "  # Check pinned versions:"
  echo "  /isaac-sim/python.sh -m pip show numpy opencv-python toml"
  echo "========================================================"
fi

exit $deploy_status
