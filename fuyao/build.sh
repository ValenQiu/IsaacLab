#!/bin/bash
container_type="isaaclab"

image_registry_url="xrobot-infra-registry.cn-wulanchabu.cr.aliyuncs.com/xrobot-infra"
current_date=$(date +"%Y.%m.%d")
image_tag="$image_registry_url/$container_type:$current_date"

# Go to the project root
cd "$(dirname "$0")/.."

echo "Start building docker image $image_tag"
# Use docker compose build directly (same as container_interface.py step 1 only).
# Do NOT call run.sh build — that triggers container.py start() which also runs
# "docker compose up", starting the full Isaac Sim container unnecessarily.
docker compose --file docker/docker-compose.yaml --env-file docker/.env.base build isaac-lab-base

# Tag the compose-produced image for the xrobot-infra registry
docker tag isaac-lab-base "$image_tag"

if [[ "${1:-}" == "--push" ]]; then
  echo "Pushing docker image $image_tag"
  # Disable BuildKit provenance/SBOM attestation so Fuyao's build server
  # receives a plain single-manifest image instead of a manifest list.
  BUILDX_NO_DEFAULT_ATTESTATIONS=1 docker push "$image_tag"
  echo ""
  echo "[INFO] Pushed image tag: $image_tag"
  echo "Next: update fuyao/fuyao.Dockerfile second FROM line with:"
  echo "  $image_tag"
fi
