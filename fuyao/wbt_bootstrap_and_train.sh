#!/bin/bash

# whole_body_tracking 训练启动脚本（供 fuyao_deploy.sh 调用）

set -euo pipefail

WBT_REPO_URL="${WBT_REPO_URL:-https://github.com/ValenQiu/whole_body_tracking.git}"
WBT_BRANCH="${WBT_BRANCH:-fast_bm_training}"
WBT_CLONE_DIR="${WBT_CLONE_DIR:-/code/source/whole_body_tracking}"
WBT_SCRIPT="${WBT_SCRIPT:-scripts/rsl_rl/train_fast.py}"
WBT_TASK="${WBT_TASK:-Tracking-Fast-Full-G1-v0}"
WBT_REGISTRY_NAME="${WBT_REGISTRY_NAME:-liuming-valen-qiu-the-hong-kong-polytechnic-university-org/wandb-registry-Motions/walk2_subject4}"
WBT_RUN_NAME="${WBT_RUN_NAME:-walk2_subject4_full}"
WBT_LOG_PROJECT_NAME="${WBT_LOG_PROJECT_NAME:-g1_fast_tracking_test}"
WBT_MAX_ITERATIONS="${WBT_MAX_ITERATIONS:-30000}"
WBT_ASSET_URL="${WBT_ASSET_URL:-https://storage.googleapis.com/qiayuanl_robot_descriptions/unitree_description.tar.gz}"
WBT_URDF_PATH="${WBT_CLONE_DIR}/source/whole_body_tracking/whole_body_tracking/assets/unitree_description/urdf/g1/main.urdf"
WBT_ASSET_DIR="${WBT_CLONE_DIR}/source/whole_body_tracking/whole_body_tracking/assets"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-url) WBT_REPO_URL="$2"; shift 2 ;;
        --branch) WBT_BRANCH="$2"; shift 2 ;;
        --clone-dir) WBT_CLONE_DIR="$2"; shift 2 ;;
        --script) WBT_SCRIPT="$2"; shift 2 ;;
        --task) WBT_TASK="$2"; shift 2 ;;
        --registry-name) WBT_REGISTRY_NAME="$2"; shift 2 ;;
        --run-name) WBT_RUN_NAME="$2"; shift 2 ;;
        --log-project) WBT_LOG_PROJECT_NAME="$2"; shift 2 ;;
        --max-iterations) WBT_MAX_ITERATIONS="$2"; shift 2 ;;
        --asset-url) WBT_ASSET_URL="$2"; shift 2 ;;
        *)
            echo "[ERROR] Unknown argument: $1"
            exit 1
            ;;
    esac
done

WBT_URDF_PATH="${WBT_CLONE_DIR}/source/whole_body_tracking/whole_body_tracking/assets/unitree_description/urdf/g1/main.urdf"
WBT_ASSET_DIR="${WBT_CLONE_DIR}/source/whole_body_tracking/whole_body_tracking/assets"

if [[ ! -d "$WBT_CLONE_DIR" ]]; then
    echo "[INFO] cloning whole_body_tracking from $WBT_REPO_URL ($WBT_BRANCH)"
    git clone -b "$WBT_BRANCH" "$WBT_REPO_URL" "$WBT_CLONE_DIR"
fi

echo "[INFO] ensure wandb/protobuf versions"
/workspace/isaaclab/_isaac_sim/python.sh -m pip install -U \
    "wandb>=0.19" "protobuf>=3.20.2,<5.0.0" \
    -i http://mirrors.aliyun.com/pypi/simple --trusted-host mirrors.aliyun.com

if [[ ! -s "/code/wandb_api_key.txt" ]]; then
    echo "[ERROR] /code/wandb_api_key.txt not found or empty"
    exit 1
fi

export WANDB_API_KEY="$(head -n 1 /code/wandb_api_key.txt | tr -d '\r' | xargs)"
if [[ -z "${WANDB_API_KEY}" ]]; then
    echo "[ERROR] WANDB_API_KEY is empty after parsing /code/wandb_api_key.txt"
    exit 1
fi

if [[ ! -f "$WBT_URDF_PATH" ]]; then
    echo "[INFO] downloading robot asset to $WBT_ASSET_DIR"
    curl -L -o /tmp/unitree_description.tar.gz "$WBT_ASSET_URL"
    tar -xzf /tmp/unitree_description.tar.gz -C "$WBT_ASSET_DIR"
    rm -f /tmp/unitree_description.tar.gz
fi

cd "$WBT_CLONE_DIR"
echo "[INFO] launch training: task=$WBT_TASK, registry=$WBT_REGISTRY_NAME"
/workspace/isaaclab/_isaac_sim/python.sh "$WBT_SCRIPT" \
    --task="$WBT_TASK" \
    --registry_name="$WBT_REGISTRY_NAME" \
    --run_name="$WBT_RUN_NAME" \
    --headless \
    --logger=wandb \
    --log_project_name="$WBT_LOG_PROJECT_NAME" \
    --max_iterations="$WBT_MAX_ITERATIONS"
