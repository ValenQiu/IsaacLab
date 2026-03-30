# Docker 开发环境使用说明

本目录包含 IsaacLab 的容器化开发环境所需的全部配置和脚本。

---

## 快速上手

```bash
# 在项目根目录执行
./docker/run.sh start   # 构建镜像（首次）并启动容器
./docker/run.sh enter   # 进入容器 Shell
./docker/run.sh stop    # 停止并删除容器
```

---

## 文件说明

| 文件 | 说明 |
|---|---|
| `run.sh` | **推荐入口**。在 `container.py` 基础上增加了 SSH agent 转发和工作区自动初始化 |
| `setup_workspace.sh` | 在容器内部运行，自动 clone 并安装 `whole_body_tracking` |
| `container.py` | 上游原始容器管理脚本（X11、docker-compose 编排等） |
| `docker-compose.yaml` | 容器服务定义（卷挂载、GPU、网络等） |
| `Dockerfile.base` | 基础镜像构建文件（Isaac Sim + Isaac Lab） |
| `Dockerfile.ros2` | 在基础镜像上叠加 ROS2 Humble |
| `x11.yaml` | X11 转发的 compose 扩展配置 |
| `.env.base` | 环境变量（Isaac Sim 版本、容器内路径等） |

---

## run.sh 命令参考

```
./docker/run.sh <command> [container.py 透传参数]
```

| 命令 | 说明 |
|---|---|
| `build` | 构建 Docker 镜像（不启动容器） |
| `start` | 启动容器，自动完成 SSH agent 配置和工作区初始化 |
| `enter` | 进入正在运行的容器，打开交互式 bash |
| `stop` | 停止并删除容器 |
| `help` | 打印帮助信息 |

`container.py` 支持的所有参数均可直接追加，例如：

```bash
./docker/run.sh start ros2                        # 使用 ros2 profile
./docker/run.sh start --env-files .env.myconfig   # 额外 env 文件
./docker/run.sh enter ros2                        # 进入 ros2 容器
```

---

## 功能详解

### X11 图形转发

由 `container.py` 与 `x11.yaml` 原生支持，使用 `xauth` + MIT-MAGIC-COOKIE 方案。
首次执行 `start` 时会询问是否启用，选择会保存到 `docker/.container.cfg`，后续自动沿用。

> 若需修改，直接编辑 `.container.cfg` 中的 `X11_FORWARDING_ENABLED` 字段（`1` 启用，`0` 禁用）。

### SSH Agent 转发

`run.sh start` 会检测宿主机的 `$SSH_AUTH_SOCK`，若存在则自动将 SSH agent socket 挂载进容器，使容器内的 `git` 操作能直接使用宿主机上已加载的 SSH 密钥，无需在容器内重复配置密钥。

**前提条件：** 宿主机上 SSH agent 已启动且已加载密钥。

```bash
# 检查 agent 是否运行及已加载的密钥
ssh-add -l

# 若 agent 未启动或未加载密钥
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519   # 替换为实际的私钥路径
```

### 宿主机与容器文件共享

以下目录通过 bind mount 实时双向同步，**停止容器不会丢失数据**：

| 宿主机路径 | 容器内路径 |
|---|---|
| `source/` | `/workspace/isaaclab/source/` |
| `scripts/` | `/workspace/isaaclab/scripts/` |
| `docs/` | `/workspace/isaaclab/docs/` |
| `tools/` | `/workspace/isaaclab/tools/` |

Isaac Sim 的缓存、日志等通过 Docker named volume 持久化，容器重建后仍然保留。

### 工作区自动初始化（whole_body_tracking）

每次执行 `./docker/run.sh start` 时，脚本会在容器内自动运行 `setup_workspace.sh`，完成以下操作：

1. 将 `github.com` 加入容器的 SSH `known_hosts`（幂等）
2. 若 `source/whole_body_tracking/` 不存在，则通过 SSH clone：
   ```
   git@github.com:ValenQiu/whole_body_tracking.git
   ```
   clone 目标在 bind mount 路径内，**结果同时出现在宿主机的 `source/whole_body_tracking/`**，停止容器不会丢失。
3. 执行 `pip install -e source/whole_body_tracking`，恢复 editable install 注册（容器重建后 pip 注册会丢失，此步骤自动补回）。

> `source/whole_body_tracking/` 已加入 `.gitignore`，不会被提交到 IsaacLab 仓库。

---

## 典型工作流

### 首次使用

```bash
# 1. 确认宿主机 SSH agent 已加载密钥
ssh-add -l

# 2. 启动容器（首次会自动构建镜像，耗时较长）
./docker/run.sh start

# 3. 进入容器
./docker/run.sh enter

# 4. 在容器内运行训练脚本（示例）
cd /workspace/isaaclab
python source/whole_body_tracking/scripts/rsl_rl/train.py --task=...
```

### 日常开发

```bash
./docker/run.sh start    # 启动（镜像已存在时很快）
./docker/run.sh enter    # 开发...
./docker/run.sh stop     # 收工
```

### 重新构建镜像

```bash
./docker/run.sh stop     # 先停止旧容器
./docker/run.sh build    # 重新构建
./docker/run.sh start    # 启动新容器
```

---

## 常见问题

**Q: `start` 时提示 `SSH_AUTH_SOCK not set`，clone 失败怎么办？**

在宿主机上启动 SSH agent 并加载密钥后重试：
```bash
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519
./docker/run.sh stop && ./docker/run.sh start
```

**Q: X11 窗口无法显示？**

确认 `DISPLAY` 变量已设置（`echo $DISPLAY`），然后检查 `.container.cfg` 中 `X11_FORWARDING_ENABLED=1`。也可以删除该文件，下次 `start` 时重新配置。

**Q: `whole_body_tracking` 的代码改动在容器外能看到吗？**

可以。`source/` 目录是 bind mount，容器内的任何修改实时反映到宿主机的 `source/whole_body_tracking/`，可直接用宿主机的编辑器开发。

**Q: 停止容器后再次 `start`，`whole_body_tracking` 还在吗？**

源码文件在宿主机 `source/whole_body_tracking/`，**不会丢失**。pip editable install 注册会在每次 `start` 时自动恢复。
