#!/bin/bash

# fuyao 远程内核 SSH 连接脚本
# 用法: ./fuyao_remote_kernel_ssh.sh --job_name <job_name> [选项]

set -e

# 默认配置
DEFAULT_SITE="fuyao_sh_n2"
DEFAULT_INSTANCE_TYPE="remoteKernel"
DEFAULT_IDENTITY_FILE="~/.ssh/id_ed25519"
DEFAULT_CONFIG_ONLY="true"

# 初始化变量
job_name=""
site="$DEFAULT_SITE"
instance_type="$DEFAULT_INSTANCE_TYPE"
identity_file="$DEFAULT_IDENTITY_FILE"
config_only="$DEFAULT_CONFIG_ONLY"

# 显示帮助信息
show_help() {
    echo "用法: $0 --job_name <job_name> [选项]"
    echo ""
    echo "fuyao 远程内核 SSH 连接脚本"
    echo ""
    echo "必需参数:"
    echo "  --job_name <name>          远程内核任务名称 (必需)"
    echo ""
    echo "可选参数:"
    echo "  --site <site>              fuyao 站点 (默认: $DEFAULT_SITE)"
    echo "  --instance_type <type>     实例类型 (默认: $DEFAULT_INSTANCE_TYPE)"
    echo "  --identity_file <path>     SSH 密钥文件路径 (默认: $DEFAULT_IDENTITY_FILE)"
    echo "  --config_only <bool>       仅生成配置，不连接 (默认: $DEFAULT_CONFIG_ONLY)"
    echo "  -h, --help                 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 --job_name my-remote-kernel-123456"
    echo "  $0 --job_name my-kernel --site fuyao_bj --config_only false"
    echo "  $0 --job_name my-kernel --identity_file ~/.ssh/id_rsa"
    exit 0
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --job_name)
            job_name="$2"
            shift 2
            ;;
        --site)
            site="$2"
            shift 2
            ;;
        --instance_type)
            instance_type="$2"
            shift 2
            ;;
        --identity_file)
            identity_file="$2"
            shift 2
            ;;
        --config_only)
            config_only="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "[ERROR] 未知参数: $1"
            echo "使用 -h 或 --help 查看帮助信息"
            exit 1
            ;;
    esac
done

# 检查必需参数
if [ -z "$job_name" ]; then
    echo "[ERROR] 必须指定 --job_name 参数"
    echo "使用 -h 或 --help 查看帮助信息"
    exit 1
fi

echo "[INFO] ========== SSH 连接配置 =========="
echo "[INFO] 任务名称: $job_name"
echo "[INFO] 站点: $site"
echo "[INFO] 实例类型: $instance_type"
echo "[INFO] 密钥文件: $identity_file"
echo "[INFO] 仅生成配置: $config_only"
echo "[INFO] ==================================="
echo ""

# 执行 fuyao ssh 命令
echo "[INFO] 正在连接远程内核..."
fuyao ssh \
    --instance-name="$job_name" \
    --site="$site" \
    --instance-type="$instance_type" \
    --identity-file-path="$identity_file" \
    --config-only "$config_only"
