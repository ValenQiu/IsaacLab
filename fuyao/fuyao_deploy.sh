#!/bin/bash

# IsaacLab fuyao 批量 job 部署脚本（GPU 模式）
# 用法: ./fuyao_deploy.sh [--run_cmd "bash ./scripts/xxx.sh [args...]"] [其他选项]

set -e

# Load optional local config: fuyao/.env
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/.env"
fi

# Fallback: if WANDB_API_KEY not set in fuyao/.env, try local key file.
if [[ -z "${WANDB_API_KEY:-}" && -f "$HOME/.wandb_api_key" ]]; then
  WANDB_API_KEY="$(head -n 1 "$HOME/.wandb_api_key" | tr -d '\r' | xargs)"
fi

# 默认配置
DEFAULT_IMAGE="${DEFAULT_IMAGE:-infra-registry-vpc.cn-wulanchabu.cr.aliyuncs.com/data-infra/fuyao:isaaclab-260404-0534}"
DEFAULT_PROJECT="${DEFAULT_PROJECT:-rc-wbc}"
DEFAULT_SITE="${DEFAULT_SITE:-fuyao_sh_n2}"
DEFAULT_QUEUE="${DEFAULT_QUEUE:-rc-wbc-4090}"
DEFAULT_EXPERIMENT="${DEFAULT_EXPERIMENT:-}"
DEFAULT_GPUS="${DEFAULT_GPUS:-1}"
DEFAULT_NODES="${DEFAULT_NODES:-1}"
DEFAULT_LABEL="${DEFAULT_LABEL:-test}"
DEFAULT_VOLUME="${DEFAULT_VOLUME:-rc-wbc}"
DEFAULT_RUN_CMD="bash ./scripts/train.sh"
DEFAULT_WBT_REPO_URL="${DEFAULT_WBT_REPO_URL:-https://github.com/ValenQiu/whole_body_tracking.git}"
DEFAULT_WBT_BRANCH="${DEFAULT_WBT_BRANCH:-fast_bm_training}"
DEFAULT_WBT_CLONE_DIR="${DEFAULT_WBT_CLONE_DIR:-/code/source/whole_body_tracking}"
DEFAULT_WBT_SCRIPT="${DEFAULT_WBT_SCRIPT:-scripts/rsl_rl/train_fast.py}"
DEFAULT_WBT_TASK="${DEFAULT_WBT_TASK:-Tracking-Fast-Full-G1-v0}"
DEFAULT_WBT_REGISTRY_NAME="${DEFAULT_WBT_REGISTRY_NAME:-liuming-valen-qiu-the-hong-kong-polytechnic-university-org/wandb-registry-Motions/walk2_subject4}"
DEFAULT_WBT_RUN_NAME="${DEFAULT_WBT_RUN_NAME:-walk2_subject4_full}"
DEFAULT_WBT_LOG_PROJECT_NAME="${DEFAULT_WBT_LOG_PROJECT_NAME:-g1_fast_tracking_test}"
DEFAULT_WBT_MAX_ITERATIONS="${DEFAULT_WBT_MAX_ITERATIONS:-30000}"
DEFAULT_WBT_ASSET_URL="${DEFAULT_WBT_ASSET_URL:-https://storage.googleapis.com/qiayuanl_robot_descriptions/unitree_description.tar.gz}"

# 初始化变量
image="$DEFAULT_IMAGE"
project="$DEFAULT_PROJECT"
site="$DEFAULT_SITE"
queue="$DEFAULT_QUEUE"
experiment="$DEFAULT_EXPERIMENT"
gpus="$DEFAULT_GPUS"
nodes="$DEFAULT_NODES"
label="$DEFAULT_LABEL"
volume="$DEFAULT_VOLUME"
run_cmd="$DEFAULT_RUN_CMD"
wbt_repo_url="$DEFAULT_WBT_REPO_URL"
wbt_branch="$DEFAULT_WBT_BRANCH"
wbt_clone_dir="$DEFAULT_WBT_CLONE_DIR"
wbt_script="$DEFAULT_WBT_SCRIPT"
wbt_task="$DEFAULT_WBT_TASK"
wbt_registry_name="$DEFAULT_WBT_REGISTRY_NAME"
wbt_run_name="$DEFAULT_WBT_RUN_NAME"
wbt_log_project_name="$DEFAULT_WBT_LOG_PROJECT_NAME"
wbt_max_iterations="$DEFAULT_WBT_MAX_ITERATIONS"
wbt_asset_url="$DEFAULT_WBT_ASSET_URL"
auto_wbt_cmd=false

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "可选参数:"
    echo "  --run_cmd <cmd>        要在 fuyao 上执行的命令 (默认: $DEFAULT_RUN_CMD)"
    echo "  --image <image>        Docker 镜像 (默认: $DEFAULT_IMAGE)"
    echo "  --project <project>    fuyao 项目名 (默认: $DEFAULT_PROJECT)"
    echo "  --site <site>          fuyao 站点 (默认: $DEFAULT_SITE)"
    echo "  --queue <queue>        fuyao 队列 (默认: $DEFAULT_QUEUE)"
    echo "  --experiment <exp>     实验名称 (默认: $DEFAULT_EXPERIMENT)"
    echo "  --gpus <num>           每节点 GPU 数量 (默认: $DEFAULT_GPUS)"
    echo "  --nodes <num>          节点数量 (默认: $DEFAULT_NODES)"
    echo "  --label <label>        任务标签 (默认: $DEFAULT_LABEL)"
    echo "  --volume <volume>      挂载卷 (默认: $DEFAULT_VOLUME)"
    echo ""
    echo "whole_body_tracking 训练快捷参数（可替代 --run_cmd）:"
    echo "  --wbt-train-fast-full  自动执行 clone+依赖+wandb+asset+train_fast"
    echo "  --wbt-repo-url <url>   whole_body_tracking 仓库地址 (默认: $DEFAULT_WBT_REPO_URL)"
    echo "  --wbt-branch <branch>  whole_body_tracking 分支 (默认: $DEFAULT_WBT_BRANCH)"
    echo "  --wbt-clone-dir <dir>  容器内克隆路径 (默认: $DEFAULT_WBT_CLONE_DIR)"
    echo "  --wbt-script <path>    训练脚本路径 (默认: $DEFAULT_WBT_SCRIPT)"
    echo "  --wbt-task <task>      task 名 (默认: $DEFAULT_WBT_TASK)"
    echo "  --wbt-registry <name>  registry_name (默认: $DEFAULT_WBT_REGISTRY_NAME)"
    echo "  --wbt-run-name <name>  run_name (默认: $DEFAULT_WBT_RUN_NAME)"
    echo "  --wbt-log-project <p>  log_project_name (默认: $DEFAULT_WBT_LOG_PROJECT_NAME)"
    echo "  --wbt-max-iters <n>    max_iterations (默认: $DEFAULT_WBT_MAX_ITERATIONS)"
    echo "  --wbt-asset-url <url>  unitree_description 下载地址 (默认: $DEFAULT_WBT_ASSET_URL)"
    echo "  -h, --help             显示此帮助信息"
    exit 0
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --run_cmd)   run_cmd="$2";    shift 2 ;;
        --image)     image="$2";      shift 2 ;;
        --project)   project="$2";    shift 2 ;;
        --site)      site="$2";       shift 2 ;;
        --queue)     queue="$2";      shift 2 ;;
        --experiment) experiment="$2"; shift 2 ;;
        --gpus)      gpus="$2";       shift 2 ;;
        --nodes)     nodes="$2";      shift 2 ;;
        --label)     label="$2";      shift 2 ;;
        --volume)    volume="$2";     shift 2 ;;
        --wbt-train-fast-full) auto_wbt_cmd=true; shift ;;
        --wbt-repo-url) wbt_repo_url="$2"; shift 2 ;;
        --wbt-branch) wbt_branch="$2"; shift 2 ;;
        --wbt-clone-dir) wbt_clone_dir="$2"; shift 2 ;;
        --wbt-script) wbt_script="$2"; shift 2 ;;
        --wbt-task) wbt_task="$2"; shift 2 ;;
        --wbt-registry) wbt_registry_name="$2"; shift 2 ;;
        --wbt-run-name) wbt_run_name="$2"; shift 2 ;;
        --wbt-log-project) wbt_log_project_name="$2"; shift 2 ;;
        --wbt-max-iters) wbt_max_iterations="$2"; shift 2 ;;
        --wbt-asset-url) wbt_asset_url="$2"; shift 2 ;;
        -h|--help)   show_help ;;
        *)
            echo "[ERROR] 未知参数: $1"
            echo "使用 -h 或 --help 查看帮助信息"
            exit 1
            ;;
    esac
done

if [[ -z "$experiment" ]]; then
    echo "[ERROR] --experiment is required"
    exit 1
fi

if [[ -z "$site" ]]; then
    echo "[ERROR] --site is required"
    exit 1
fi

if [[ "$auto_wbt_cmd" == "true" ]]; then
    run_cmd="bash fuyao/wbt_bootstrap_and_train.sh \
--repo-url=${wbt_repo_url} \
--branch=${wbt_branch} \
--clone-dir=${wbt_clone_dir} \
--script=${wbt_script} \
--task=${wbt_task} \
--registry-name=${wbt_registry_name} \
--run-name=${wbt_run_name} \
--log-project=${wbt_log_project_name} \
--max-iterations=${wbt_max_iterations} \
--asset-url=${wbt_asset_url}"
fi

echo "[INFO] 执行命令: $run_cmd"
echo "[INFO] Docker 镜像: $image"
echo "[INFO] 项目: $project, 站点: $site, 队列: $queue"
echo "[INFO] 实验: $experiment, GPUs/节点: $gpus, 节点数: $nodes"
echo ""

# 切换到脚本所在目录的上一级（项目根目录）
cd "$SCRIPT_DIR/.." || exit 1

# 创建带时间戳的临时目录
stamp=$(date +%Y%m%d%H%M%S%N)
tmp_dir="/tmp/fuyao_deploy_${stamp}"

echo "[INFO] 创建临时目录: $tmp_dir"
rm -rf "$tmp_dir"
mkdir -p "$tmp_dir"

# 使用 rsync 同步文件，通过 .gitignore 过滤
echo "[INFO] 同步文件到临时目录（使用 .gitignore 过滤）..."
if ! rsync -a --filter=':- .gitignore' . "$tmp_dir/"; then
    echo "[ERROR] rsync 同步失败"
    rm -rf "$tmp_dir"
    exit 1
fi
echo "[INFO] 文件同步完成"

# Inject secret to temp snapshot (gitignored in source tree).
if [[ -n "${WANDB_API_KEY:-}" ]]; then
    echo "[INFO] 注入 WANDB_API_KEY 到临时快照 wandb_api_key.txt"
    printf '%s\n' "$WANDB_API_KEY" > "$tmp_dir/wandb_api_key.txt"
    chmod 600 "$tmp_dir/wandb_api_key.txt"
fi

# 切换到临时目录进行部署
cd "$tmp_dir" || exit 1

# 部署任务
echo "[INFO] 开始部署任务..."
deploy_status=0
fuyao deploy \
    --docker-image="$image" \
    --project="$project" \
    --site="$site" \
    --queue="$queue" \
    --experiment="$experiment" \
    --volume="$volume" \
    --nodes="$nodes" \
    --gpus-per-node="$gpus" \
    --label="$label" \
    --ignore-artifact-size \
    "$run_cmd" || deploy_status=$?

# 清理临时目录
echo "[INFO] 清理临时目录: $tmp_dir"
rm -rf "$tmp_dir"

if [ $deploy_status -ne 0 ]; then
    echo "[ERROR] 部署失败，退出码: $deploy_status"
fi

exit $deploy_status
