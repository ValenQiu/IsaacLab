#!/usr/bin/env bash
# =============================================================================
# remote_kernel_bootstrap.sh — Fuyao remote kernel container init
#
# Runs on every container start (idempotent). Handles:
#   1. _isaac_sim symlink creation (bind-mount can't persist symlinks)
#   2. SSH known_hosts for github.com
#   3. whole_body_tracking clone + editable install
#   4. wandb/protobuf + numpy/opencv pin enforcement
#   5. W&B non-interactive auth bootstrap
#   6. Health checks
# Then hands off to the platform's remote-kernel-entrypoint.
# =============================================================================
set -u

LOG_FILE="/opt/data-infra/remote-kernel-bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================================"
echo "[bootstrap] start at $(date '+%F %T')"
echo "========================================================"

ISAACLAB_SOURCE="${ISAACLAB_PATH:-/workspace/qiulm@xiaopeng.com/source/IsaacLab}"
WBT_DIR="${ISAACLAB_SOURCE}/source/whole_body_tracking"
WBT_PKG_DIR="${WBT_DIR}/source/whole_body_tracking"
WBT_REPO="${WBT_REPO:-git@github.com:ValenQiu/whole_body_tracking.git}"
WBT_BRANCH="${WBT_BRANCH:-fast_bm_training}"
PY="/isaac-sim/python.sh"
REMOTE_KERNEL_ENTRYPOINT="/workspace/training_common/remote-kernel-entrypoint.sh"
SECRET_WANDB_KEY_FILE="${ISAACLAB_SOURCE}/.remote_secrets/wandb_api_key"
WBT_ASSET_URL="${WBT_ASSET_URL:-https://storage.googleapis.com/qiayuanl_robot_descriptions/unitree_description.tar.gz}"
WBT_ASSET_DIR="${WBT_PKG_DIR}/whole_body_tracking/assets"
WBT_URDF_PATH="${WBT_ASSET_DIR}/unitree_description/urdf/g1/main.urdf"

ALIYUN_MIRROR="-i http://mirrors.aliyun.com/pypi/simple --trusted-host mirrors.aliyun.com"

step_start() { STEP_T0=$(date +%s); echo "[bootstrap][$1] start ..."; }
step_done()  { echo "[bootstrap][$1] done ($(( $(date +%s) - STEP_T0 ))s)"; }

# --- Step 1: _isaac_sim symlink -------------------------------------------
create_isaac_sim_symlink() {
    step_start "symlink"
    if [[ -d "$ISAACLAB_SOURCE" && ! -L "$ISAACLAB_SOURCE/_isaac_sim" ]]; then
        ln -sf /isaac-sim "$ISAACLAB_SOURCE/_isaac_sim" 2>/dev/null || true
        echo "[bootstrap][symlink] created $ISAACLAB_SOURCE/_isaac_sim -> /isaac-sim"
    else
        echo "[bootstrap][symlink] already exists or source dir missing, skip"
    fi
    step_done "symlink"
}

# --- Step 2: SSH known_hosts for github.com --------------------------------
add_known_host() {
    step_start "ssh"
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    if ! ssh-keygen -F github.com >/dev/null 2>&1; then
        ssh-keyscan -H github.com >> ~/.ssh/known_hosts 2>/dev/null || true
        echo "[bootstrap][ssh] added github.com to known_hosts"
    else
        echo "[bootstrap][ssh] github.com already in known_hosts, skip"
    fi
    step_done "ssh"
}

# --- Step 3: Clone whole_body_tracking if missing --------------------------
clone_wbt_if_needed() {
    step_start "clone"
    if [[ -f "${WBT_DIR}/pyproject.toml" ]]; then
        echo "[bootstrap][clone] whole_body_tracking exists, skip"
        step_done "clone"
        return 0
    fi
    echo "[bootstrap][clone] cloning ${WBT_REPO} branch=${WBT_BRANCH} ..."
    if GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=accept-new' \
       git clone -b "${WBT_BRANCH}" "${WBT_REPO}" "${WBT_DIR}"; then
        echo "[bootstrap][clone] clone succeeded"
    else
        echo "[bootstrap][clone][ERROR] clone failed — check SSH agent / key forwarding"
        echo "[bootstrap][clone][HINT]  ensure your fuyao deploy has SSH agent forwarding enabled"
        step_done "clone"
        return 1
    fi
    step_done "clone"
}

# --- Step 4: Ensure required model assets ----------------------------------
ensure_wbt_assets() {
    step_start "assets"
    if [[ ! -d "$WBT_PKG_DIR" ]]; then
        echo "[bootstrap][assets] $WBT_PKG_DIR not found, skip assets bootstrap"
        step_done "assets"
        return 1
    fi

    if [[ -f "$WBT_URDF_PATH" ]]; then
        echo "[bootstrap][assets] unitree_description already exists, skip"
        step_done "assets"
        return 0
    fi

    mkdir -p "$WBT_ASSET_DIR"
    local tmp_tar
    tmp_tar="$(mktemp /tmp/unitree_description.XXXXXX.tar.gz)"
    echo "[bootstrap][assets] downloading unitree_description from ${WBT_ASSET_URL}"
    if ! curl -L --fail -o "$tmp_tar" "$WBT_ASSET_URL"; then
        echo "[bootstrap][assets][ERROR] failed to download asset archive"
        rm -f "$tmp_tar"
        step_done "assets"
        return 1
    fi

    if ! tar -xzf "$tmp_tar" -C "$WBT_ASSET_DIR"; then
        echo "[bootstrap][assets][ERROR] failed to extract asset archive"
        rm -f "$tmp_tar"
        step_done "assets"
        return 1
    fi
    rm -f "$tmp_tar"

    if [[ ! -f "$WBT_URDF_PATH" ]]; then
        echo "[bootstrap][assets][ERROR] asset extracted but expected URDF missing: $WBT_URDF_PATH"
        step_done "assets"
        return 1
    fi

    echo "[bootstrap][assets] unitree_description is ready"
    step_done "assets"
}

# --- Step 5: Editable install + pin deps -----------------------------------
install_and_pin() {
    step_start "install"
    if [[ ! -d "$WBT_PKG_DIR" ]]; then
        echo "[bootstrap][install] $WBT_PKG_DIR not found, skip install"
        step_done "install"
        return 1
    fi
    echo "[bootstrap][install] pip install -e ${WBT_PKG_DIR}"
    if "${PY}" -m pip install -e "${WBT_PKG_DIR}" ${ALIYUN_MIRROR}; then
        echo "[bootstrap][install] editable install succeeded"
    else
        echo "[bootstrap][install][ERROR] pip install -e failed"
        step_done "install"
        return 1
    fi

    echo "[bootstrap][install] hard pin wandb/protobuf (required by training preflight) ..."
    # Hard-coded by design: keep this exact command to avoid environment drift
    # across newly created remote kernels.
    /workspace/isaaclab/_isaac_sim/python.sh -m pip install -U "wandb>=0.19" "protobuf>=3.20.2,<5.0.0" -i http://mirrors.aliyun.com/pypi/simple --trusted-host mirrors.aliyun.com

    echo "[bootstrap][install] re-pinning numpy/opencv ..."
    "${PY}" -m pip install \
        "numpy==1.26.4" \
        "opencv-python==4.9.0.80" \
        ${ALIYUN_MIRROR}
    step_done "install"
}

# --- Step 6: W&B auth bootstrap -------------------------------------------
ensure_wandb_auth() {
    step_start "wandb-auth"
    local key=""

    if [[ -n "${WANDB_API_KEY:-}" ]]; then
        key="${WANDB_API_KEY}"
        echo "[bootstrap][wandb-auth] using WANDB_API_KEY from env"
    elif [[ -f "${SECRET_WANDB_KEY_FILE}" ]]; then
        key="$(head -n 1 "${SECRET_WANDB_KEY_FILE}" | tr -d '\r' | xargs)"
        echo "[bootstrap][wandb-auth] using key from ${SECRET_WANDB_KEY_FILE}"
    elif [[ -f "/root/.wandb_api_key" ]]; then
        key="$(head -n 1 /root/.wandb_api_key | tr -d '\r' | xargs)"
        echo "[bootstrap][wandb-auth] using key from /root/.wandb_api_key"
    fi

    if [[ -n "${key}" ]]; then
        export WANDB_API_KEY="${key}"
        printf '%s\n' "${key}" > /root/.wandb_api_key
        chmod 600 /root/.wandb_api_key
        "${PY}" - <<'PY'
import os
import wandb
key = os.environ.get("WANDB_API_KEY", "").strip()
if key:
    wandb.login(key=key, relogin=False)
    print("[bootstrap][wandb-auth] wandb login ensured.")
PY
    else
        echo "[bootstrap][wandb-auth][WARN] no WANDB_API_KEY found. wandb may prompt interactively."
    fi
    step_done "wandb-auth"
}

# --- Step 7: Health check --------------------------------------------------
health_check() {
    step_start "health"
    if "${PY}" -c "import toml, requests, torch, isaaclab; print('core imports ok')"; then
        echo "[bootstrap][health] core imports passed"
    else
        echo "[bootstrap][health][WARN] core imports failed"
    fi

    "${PY}" -m pip check 2>&1 || echo "[bootstrap][health][WARN] pip check reported conflicts"

    echo "[bootstrap][health] key package versions:"
    "${PY}" -m pip show numpy opencv-python toml wandb protobuf 2>/dev/null \
        | grep -E "^(Name|Version):" || true
    step_done "health"
}

# --- Execute ---------------------------------------------------------------
create_isaac_sim_symlink
add_known_host
clone_wbt_if_needed   || echo "[bootstrap][WARN] clone step failed, continuing ..."
ensure_wbt_assets     || echo "[bootstrap][WARN] assets step failed, continuing ..."
install_and_pin       || echo "[bootstrap][WARN] install/pin step failed, continuing ..."
ensure_wandb_auth     || echo "[bootstrap][WARN] wandb auth step failed, continuing ..."
health_check          || echo "[bootstrap][WARN] health check failed, continuing ..."

echo "========================================================"
echo "[bootstrap] done at $(date '+%F %T')"
echo "[bootstrap] log saved to ${LOG_FILE}"
echo "========================================================"

if [[ -x "$REMOTE_KERNEL_ENTRYPOINT" ]]; then
    echo "[bootstrap] exec -> ${REMOTE_KERNEL_ENTRYPOINT}"
    exec "$REMOTE_KERNEL_ENTRYPOINT"
else
    echo "[bootstrap] ${REMOTE_KERNEL_ENTRYPOINT} not found, falling back to exec \"\$@\""
    exec "$@"
fi
