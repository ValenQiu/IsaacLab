FROM infra-registry.cn-wulanchabu.cr.aliyuncs.com/data-infra/public:fuyao-base-1.8.7 AS data-infra

# Base image produced by: bash fuyao/build.sh --push
FROM xrobot-infra-registry.cn-wulanchabu.cr.aliyuncs.com/xrobot-infra/isaaclab:2026.04.04

ENV MAX_JOBS=1

# Fuyao runtime
COPY --from=data-infra /opt/data-infra /opt/data-infra
ENV PATH="${PATH}:/opt/data-infra"
USER root

# Fuyao SDK — only use /isaac-sim/python.sh to ensure Isaac Sim env injection.
RUN /isaac-sim/python.sh -m pip install fuyao-all \
    -i http://mirrors.aliyun.com/pypi/simple --trusted-host mirrors.aliyun.com \
    --extra-index-url http://nexus-ht.xiaopeng.link:8081/repository/ai_infra_pypi/simple --trusted-host nexus-ht.xiaopeng.link

# Fix ~/.bashrc aliases: base image points python/pip to /workspace/isaaclab/_isaac_sim/
# which does not exist in the Fuyao workspace layout. Redirect directly to /isaac-sim/.
RUN PYTHON_SH=/isaac-sim/python.sh && \
    ISAACLAB_SOURCE=/workspace/qiulm@xiaopeng.com/source/IsaacLab && \
    sed -i \
        -e "s|export ISAACLAB_PATH=.*|export ISAACLAB_PATH=${ISAACLAB_SOURCE}|g" \
        -e "s|alias isaaclab=.*|alias isaaclab='${ISAACLAB_SOURCE}/isaaclab.sh'|g" \
        -e "s|alias python=.*_isaac_sim.*|alias python='${PYTHON_SH}'|g" \
        -e "s|alias python3=.*_isaac_sim.*|alias python3='${PYTHON_SH}'|g" \
        -e "s|alias pip=.*_isaac_sim.*|alias pip='${PYTHON_SH} -m pip'|g" \
        -e "s|alias pip3=.*_isaac_sim.*|alias pip3='${PYTHON_SH} -m pip'|g" \
        -e "s|alias tensorboard=.*_isaac_sim.*|alias tensorboard='${PYTHON_SH} /isaac-sim/tensorboard'|g" \
        /root/.bashrc

# Pin critical deps for remote-kernel consistency:
# - wandb >=0.19 (supports modern API key formats)
# - protobuf <5.0.0 (IsaacLab compatibility)
# - numpy/opencv ABI-locked versions used by this project
RUN /isaac-sim/python.sh -m pip install \
    toml \
    "wandb>=0.19" \
    "protobuf>=3.20.2,<5.0.0" \
    "numpy==1.26.4" \
    "opencv-python==4.9.0.80" \
    -i http://mirrors.aliyun.com/pypi/simple --trusted-host mirrors.aliyun.com

# Build-time smoke checks — fail the build early if critical imports are broken.
RUN /isaac-sim/python.sh -c "import toml, requests, torch, isaaclab; print('smoke-check ok')"

# Bootstrap script: runs on every container start before handing off to the
# platform's remote-kernel-entrypoint. Handles _isaac_sim symlink, WBT clone,
# editable install, and dep pinning — all idempotently.
COPY fuyao/remote_kernel_bootstrap.sh /opt/data-infra/remote_kernel_bootstrap.sh
RUN chmod +x /opt/data-infra/remote_kernel_bootstrap.sh

ENTRYPOINT ["tini", "-s", "--", "/opt/data-infra/remote_kernel_bootstrap.sh"]
