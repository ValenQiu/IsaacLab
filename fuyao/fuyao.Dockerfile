FROM infra-registry.cn-wulanchabu.cr.aliyuncs.com/data-infra/public:fuyao-base-1.8.7 AS data-infra

# Base image produced by: bash fuyao/build.sh --push
FROM xrobot-infra-registry.cn-wulanchabu.cr.aliyuncs.com/xrobot-infra/isaaclab:2026.04.04

ENV MAX_JOBS=1

# Fuyao runtime
COPY --from=data-infra /opt/data-infra /opt/data-infra
ENV PATH="${PATH}:/opt/data-infra"
ENTRYPOINT ["tini", "-s", "--"]
USER root

# Fuyao SDK — Isaac Sim's Python lives at /isaac-sim/kit/python/bin/python3.10
# and is NOT on the default PATH, so `pip` is unavailable; use python -m pip.
RUN /isaac-sim/kit/python/bin/python3.10 -m pip install fuyao-all \
    -i http://mirrors.aliyun.com/pypi/simple --trusted-host mirrors.aliyun.com \
    --extra-index-url http://nexus-ht.xiaopeng.link:8081/repository/ai_infra_pypi/simple --trusted-host nexus-ht.xiaopeng.link
