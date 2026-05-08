#!/usr/bin/env bash

# Workspace initialization script — runs INSIDE the container.
# Clones the whole_body_tracking repo into source/ (which is bind-mounted to the host)
# and installs it with pip. Safe to run multiple times (idempotent).

# Do NOT use set -e here: if pip install fails partway through we still want
# the numpy/opencv pin step to run. Each critical step checks its own exit code.

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
ISAACLAB_PATH="${ISAACLAB_PATH:-/workspace/isaaclab}"
WBT_DIR="${ISAACLAB_PATH}/source/whole_body_tracking"
# The installable Python package lives one level deeper (same layout as IsaacLab itself)
WBT_PKG_DIR="${WBT_DIR}/source/whole_body_tracking"
WBT_REPO="git@github.com:ValenQiu/whole_body_tracking.git"
WBT_BRANCH="valenqiu_dev"
PYTHON="${ISAACLAB_PATH}/_isaac_sim/python.sh"
UNITREE_ASSET_URL="https://storage.googleapis.com/qiayuanl_robot_descriptions/unitree_description.tar.gz"
UNITREE_URDF_PATH="${WBT_PKG_DIR}/whole_body_tracking/assets/unitree_description/urdf/g1/main.urdf"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[setup]${NC} $*"; }
warn()  { echo -e "${YELLOW}[setup]${NC} $*"; }
error() { echo -e "${RED}[setup]${NC} $*" >&2; }

download_unitree_assets_if_needed() {
    if [ -f "$UNITREE_URDF_PATH" ]; then
        info "unitree_description already present — skipping download"
        return 0
    fi

    info "unitree_description missing, downloading required model assets ..."
    local tmp_tar
    tmp_tar="$(mktemp /tmp/unitree_description.XXXXXX.tar.gz)"

    if ! curl -L --fail -o "$tmp_tar" "$UNITREE_ASSET_URL"; then
        error "Failed to download unitree_description from: $UNITREE_ASSET_URL"
        rm -f "$tmp_tar"
        return 1
    fi

    mkdir -p "${WBT_PKG_DIR}/whole_body_tracking/assets"
    if ! tar -xzf "$tmp_tar" -C "${WBT_PKG_DIR}/whole_body_tracking/assets/"; then
        error "Failed to extract unitree_description archive"
        rm -f "$tmp_tar"
        return 1
    fi

    rm -f "$tmp_tar"
    if [ ! -f "$UNITREE_URDF_PATH" ]; then
        error "unitree_description download finished but expected URDF is still missing"
        return 1
    fi
    info "unitree_description model assets ready."
}

# ---------------------------------------------------------------------------
# 1. Trust GitHub's SSH host key (idempotent)
# ---------------------------------------------------------------------------
if ! ssh-keygen -F github.com &>/dev/null 2>&1; then
    info "Adding github.com to SSH known_hosts..."
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    ssh-keyscan -H github.com >> ~/.ssh/known_hosts 2>/dev/null
fi

# ---------------------------------------------------------------------------
# 2. Clone whole_body_tracking if the directory is absent or empty
# ---------------------------------------------------------------------------
if [ -d "$WBT_DIR" ] && [ -f "$WBT_DIR/pyproject.toml" ]; then
    info "whole_body_tracking already present at $WBT_DIR — skipping clone"
else
    info "Cloning whole_body_tracking from $WBT_REPO ..."

    # Prefer SSH-agent forwarding; fall back to accept-new for host-key only
    GIT_SSH_CMD='ssh -o StrictHostKeyChecking=accept-new'

    if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
        info "SSH agent forwarding detected (SSH_AUTH_SOCK=$SSH_AUTH_SOCK)"
        GIT_SSH_COMMAND="$GIT_SSH_CMD" git clone -b "$WBT_BRANCH" "$WBT_REPO" "$WBT_DIR" || {
            error "Git clone failed (with SSH agent)."
            return 1
        }
    else
        warn "SSH_AUTH_SOCK not available — attempting clone without agent (may fail for private repos)"
        GIT_SSH_COMMAND="$GIT_SSH_CMD" git clone -b "$WBT_BRANCH" "$WBT_REPO" "$WBT_DIR" || {
            error "Git clone failed."
            error "Make sure SSH agent forwarding is enabled: start the container with './docker/run.sh start'"
            return 1
        }
    fi
    info "Clone complete."
fi

# ---------------------------------------------------------------------------
# 3. Download required model/assets first (README sequence safeguard)
# ---------------------------------------------------------------------------
if ! download_unitree_assets_if_needed; then
    error "Model/assets bootstrap failed. Stop setup to avoid partial environment."
    exit 1
fi

# ---------------------------------------------------------------------------
# 4. Install whole_body_tracking (always run; fast if already installed)
# ---------------------------------------------------------------------------
if [ -f "$PYTHON" ]; then
    info "Installing whole_body_tracking with pip (editable mode)..."
    "$PYTHON" -m pip install --quiet -e "$WBT_PKG_DIR"

    # Isaac Sim 4.5.0 bundles scipy 1.10.1 compiled against numpy 1.x
    # (numpy>=1.19.5,<1.27.0). Some dependencies may silently upgrade numpy
    # to 2.x which breaks the scipy ABI. Pin it back after every install.
    # opencv-python>=4.10 also requires numpy>=2, so pin it to 4.9.x.
    info "Pinning numpy==1.26.4 and opencv-python==4.9.0.80 ..."
    "$PYTHON" -m pip install --quiet "numpy==1.26.4" "opencv-python==4.9.0.80"
    info "pip install done."
else
    warn "Python not found at $PYTHON — skipping pip install"
    warn "Run manually: \${ISAACLAB_PATH}/_isaac_sim/python.sh -m pip install -e $WBT_DIR"
fi

info "Workspace setup complete."
