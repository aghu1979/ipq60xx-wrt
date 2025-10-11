#!/bin/bash

# OpenWrt 构建超级辅助脚本
# 用法:
#   source scripts/build-helper.sh          # 加载日志函数到当前 shell
#   ./scripts/build-helper.sh get-devices <config_file>
#   ./scripts/build-helper.sh select-device <config_file> <device_name> <chipset>
#   ./scripts/build-helper.sh generate-notes <manifest_file> <output_file>
#   ./scripts/build-helper.sh list-third-party-packages

set -euo pipefail

# ==================== 颜色和日志函数 ====================
export COLOR_RED='\033[0;31m'
export COLOR_GREEN='\033[0;32m'
export COLOR_YELLOW='\033[1;33m'
export COLOR_BLUE='\033[0;34m'
export COLOR_PURPLE='\033[0;35m'
export COLOR_CYAN='\033[0;36m'
export COLOR_NC='\033[0m'

log_info() { echo -e "${COLOR_BLUE}[INFO]${COLOR_NC} $1" | tee -a "${LOG_FILE:-/dev/null}"; }
log_success() { echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_NC} $1" | tee -a "${LOG_FILE:-/dev/null}"; }
log_warning() { echo -e "${COLOR_YELLOW}[WARNING]${COLOR_NC} $1" | tee -a "${LOG_FILE:-/dev/null}"; }
log_error() { echo -e "${COLOR_RED}[ERROR]${COLOR_NC} $1" | tee -a "${LOG_FILE:-/dev/null}" >&2; }

# ==================== 主逻辑 ====================
COMMAND=${1:-}

if [[ -z "$COMMAND" ]]; then
    return 0
fi

case "$COMMAND" in
    get-devices)
        CONFIG_FILE=${2:-"configs/ipq60xx.base.config"}
        if [ ! -f "$CONFIG_FILE" ]; then
            log_error "配置文件 $CONFIG_FILE 不存在！"
            echo "[]"
            exit 1
        fi
        log_info "正在从 $CONFIG_FILE 提取设备名..."
        DEVICES=$(grep "^CONFIG_TARGET_DEVICE.*_DEVICE=y" "$CONFIG_FILE" | sed -n 's/^CONFIG_TARGET_DEVICE_.*_\(.*\)_DEVICE=y$/\1/p')
        if [ -z "$DEVICES" ]; then
            log_warning "在 $CONFIG_FILE 中未找到任何设备"
            echo "[]"
            exit 0
        fi
        echo "$DEVICES" | jq -R . | jq -s .
        ;;

    select-device)
        if [ "$#" -ne 4 ]; then log_error "select-device 参数错误。"; exit 1; fi
        CONFIG_FILE=$2
        DEVICE_NAME=$3
        CHIPSET=$4
        log_info "正在为架构 $CHIPSET 选择设备: $DEVICE_NAME"
        sed -i 's/^CONFIG_TARGET_DEVICE.*_DEVICE=y/# & is not set/' "$CONFIG_FILE"
        sed -i "s/^# CONFIG_TARGET_DEVICE_${CHIPSET}_${DEVICE_NAME}_DEVICE is not set/CONFIG_TARGET_DEVICE_${CHIPSET}_${DEVICE_NAME}_DEVICE=y/" "$CONFIG_FILE"
        log_success "设备选择完成。"
        ;;

    generate-notes)
        if [ "$#" -ne 3 ]; then log_error "generate-notes 参数错误。"; exit 1; fi
        MANIFEST_FILE=$1
        OUTPUT_FILE=$2
        if [ ! -f "$MANIFEST_FILE" ]; then log_error "Manifest 文件 $MANIFEST_FILE 不存在！"; exit 1; fi
        log_info "正在生成 Release Notes..."
        LUCI_APPS=$(grep -o 'luci-app-[^"]*' "$MANIFEST_FILE" | sort -u | sed 's/^/- /' || true)
        cat << EOF > "$OUTPUT_FILE"
# 🚀 OpenWrt 固件发布

本固件由 GitHub Actions 自动编译于 \$(date '+%Y-%m-%d %H:%M:%S') (UTC+8)。

---

## 📦 编译信息

- **源码分支**: \${BRANCH_NAME}
- **芯片架构**: \${CHIPSET_NAME}
- **构建环境**: \${UBUNTU_VERSION}

---

## ✨ 成功编译的 LuCI 应用

 $($LUCI_APPS)

---

## 📁 文件说明

每个附件的压缩包内包含固件、配置、清单和所有软件包。

---

## ⚠️ 重要提示

- 刷机前请务必备份。
- 本固件未集成任何第三方软件源。

Happy Hacking! 🎉
EOF
        log_success "Release Notes 生成于 $OUTPUT_FILE"
        ;;
    
    list-third-party-packages)
        if [ ! -d "package/feeds" ]; then
            log_error "Feeds 目录不存在，请先运行 feeds install。"
            exit 1
        fi
        find package/feeds -mindepth 1 -maxdepth 2 -type d -name "luci-app-*" -printf 'CONFIG_PACKAGE_%p=m\n' | sed 's|package/feeds/[^/]*/||'
        ;;

    *)
        log_error "未知命令 '$COMMAND'"
        echo "可用命令: get-devices, select-device, generate-notes, list-third-party-packages"
        exit 1
        ;;
esac
