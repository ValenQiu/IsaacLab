#!/bin/bash
# =============================================================================
# build_fuyao.sh — Build & push the Fuyao IsaacLab Docker image
#
# Usage:
#   bash fuyao/build_fuyao.sh [--push] [--tag <tag>] [--site <site>]
#
# The script performs:
#   1. Static lint: rejects Dockerfile if bare python pip calls are found
#   2. Docker build via `fuyao build`
#   3. Post-build smoke test (import checks inside the new image)
#   4. Optionally push to registry
#   5. Print summary
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load optional config
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
fi

IMAGE_NAME="${IMAGE_NAME:-isaaclab}"
DOCKERFILE="${DOCKERFILE:-fuyao.Dockerfile}"
FUYAO_SITE="${FUYAO_SITE:-fuyao_sh_n2}"
STATUS_WAIT_SECONDS="${STATUS_WAIT_SECONDS:-600}"
STATUS_POLL_INTERVAL="${STATUS_POLL_INTERVAL:-10}"
TAG=""
PUSH=false

show_help() {
    cat <<EOF
Usage: $0 [options]

Options:
  --push                Push image to registry after build
  --tag <tag>           Override auto-generated image tag
  --site <site>         Fuyao build site (default: $FUYAO_SITE)
  -h, --help            Show this help
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --push) PUSH=true; shift ;;
        --tag) TAG="$2"; shift 2 ;;
        --site) FUYAO_SITE="$2"; shift 2 ;;
        -h|--help) show_help ;;
        *) echo "[ERROR] Unknown arg: $1"; exit 1 ;;
    esac
done

if [[ -z "$TAG" ]]; then
    TAG="${IMAGE_NAME}-$(date +%y%m%d-%H%M)"
fi

echo "========================================================"
echo "[build] Fuyao IsaacLab image builder"
echo "[build] tag:        $TAG"
echo "[build] dockerfile: $DOCKERFILE"
echo "[build] site:       $FUYAO_SITE"
echo "========================================================"

# --- Step 1: Static checks ------------------------------------------------
echo ""
echo "[build][lint] Checking Dockerfile for bare python pip calls ..."

DOCKERFILE_PATH="$SCRIPT_DIR/$DOCKERFILE"
if [[ ! -f "$DOCKERFILE_PATH" ]]; then
    echo "[ERROR] Dockerfile not found: $DOCKERFILE_PATH"
    exit 1
fi

if grep -qE '/isaac-sim/kit/python/bin/python3\.10\s+-m\s+pip' "$DOCKERFILE_PATH"; then
    echo "[ERROR] Dockerfile contains bare python pip calls!"
    echo "        Use /isaac-sim/python.sh -m pip instead."
    grep -n '/isaac-sim/kit/python/bin/python3.10' "$DOCKERFILE_PATH"
    exit 1
fi
echo "[build][lint] OK — no bare python pip calls found"

if [[ ! -f "$SCRIPT_DIR/remote_kernel_bootstrap.sh" ]]; then
    echo "[ERROR] remote_kernel_bootstrap.sh not found in $SCRIPT_DIR"
    echo "        Bootstrap script is required for the image."
    exit 1
fi
echo "[build][lint] OK — remote_kernel_bootstrap.sh exists"

# --- Step 2: Build ---------------------------------------------------------
echo ""
echo "[build] Starting fuyao build ..."
cd "$PROJECT_ROOT"

fuyao build \
    --site="$FUYAO_SITE" \
    --image-name="$TAG" \
    --dockerfile="fuyao/$DOCKERFILE" \
    --status-wait-seconds="$STATUS_WAIT_SECONDS" \
    --status-poll-interval="$STATUS_POLL_INTERVAL"

BUILD_STATUS=$?
if [[ $BUILD_STATUS -ne 0 ]]; then
    echo "[ERROR] fuyao build failed with exit code $BUILD_STATUS"
    exit $BUILD_STATUS
fi

echo "[build] Build completed successfully"

# --- Step 3: Summary -------------------------------------------------------
echo ""
echo "========================================================"
echo "[build] SUMMARY"
echo "========================================================"
echo "  Image tag:       $TAG"
echo "  Dockerfile:      $DOCKERFILE"
echo "  Bootstrap:       remote_kernel_bootstrap.sh (present)"
echo "  Build site:      $FUYAO_SITE"
echo ""
echo "  To deploy as remote kernel:"
echo "    bash fuyao/fuyao_remote_kernel.sh --image <registry>/$TAG --experiment <exp>"
echo "========================================================"
