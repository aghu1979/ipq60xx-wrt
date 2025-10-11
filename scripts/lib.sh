#!/bin/bash

# OpenWrt 构建函数库
# 只用于 source 加载，提供通用函数和变量

# 设置错误处理
set -euo pipefail

# ==================== 全局变量 ====================
export COLOR_RED='\033[0;31m'
export COLOR_GREEN='\033[0;32m'
export COLOR_YELLOW='\033[1;33m'
export COLOR_BLUE='\033[0;34m'
export COLOR_PURPLE='\033[0;35m'
export COLOR_CYAN='\033[0;36m'
export COLOR_NC='\033[0m'

# 获取脚本所在目录
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 设置日志文件
export LOG_FILE="${LOG_FILE:-$PROJECT_ROOT/build.log}"

# ==================== 日志函数 ====================
log_info() { 
    echo -e "${COLOR_BLUE}[INFO]${COLOR_NC} $1" | tee -a "${LOG_FILE}" 
}

log_success() { 
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_NC} $1" | tee -a "${LOG_FILE}" 
}

log_warning() { 
    echo -e "${COLOR_YELLOW}[WARNING]${COLOR_NC} $1" | tee -a "${LOG_FILE}" 
}

log_error() { 
    echo -e "${COLOR_RED}[ERROR]${COLOR_NC} $1" | tee -a "${LOG_FILE}" >&2 
}

# ==================== 实用函数 ====================
# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查文件是否存在且非空
file_exists_and_not_empty() {
    [ -f "$1" ] && [ -s "$1" ]
}

# 安全地移动文件或目录
safe_move() {
    local src="$1"
    local dest="$2"
    
    if [ ! -e "$src" ]; then
        log_error "源文件/目录不存在: $src"
        return 1
    fi
    
    if [ -e "$dest" ]; then
        log_warning "目标文件/目录已存在，将被覆盖: $dest"
        rm -rf "$dest"
    fi
    
    mv "$src" "$dest"
    log_info "已移动: $src -> $dest"
}

# 从配置文件提取设备列表
get_devices_from_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        log_error "配置文件 $config_file 不存在！"
        echo "[]"
        return 1
    fi
    
    log_info "正在从 $config_file 提取设备名..."
    
    # 使用正则表达式提取设备名
    # 匹配模式: CONFIG_TARGET_..._DEVICE_设备名=y 或 CONFIG_TARGET_DEVICE_..._DEVICE_设备名=y
    local devices
    devices=$(grep -E "^CONFIG_TARGET(_DEVICE)?_[a-zA-Z0-9_]+_DEVICE_[a-zA-Z0-9_-]+=y" "$config_file" | \
             sed -E 's/^CONFIG_TARGET(_DEVICE)?_[a-zA-Z0-9_]+_DEVICE_([a-zA-Z0-9_-]+)=y$/\2/' | \
             sort -u)
    
    if [ -z "$devices" ]; then
        log_warning "在 $config_file 中未找到任何设备"
        echo "[]"
        return 0
    fi
    
    echo "$devices" | jq -R . | jq -s .
}

# 选择设备配置
select_device_config() {
    local config_file="$1"
    local device_name="$2"
    local chipset="$3"
    
    if [ ! -f "$config_file" ]; then
        log_error "配置文件 $config_file 不存在！"
        return 1
    fi
    
    log_info "正在为架构 $chipset 选择设备: $device_name"
    sed -i 's/^CONFIG_TARGET_DEVICE.*_DEVICE=y/# & is not set/' "$config_file"
    sed -i "s/^# CONFIG_TARGET_DEVICE_${chipset}_${device_name}_DEVICE is not set/CONFIG_TARGET_DEVICE_${chipset}_${device_name}_DEVICE=y/" "$config_file"
    log_success "设备选择完成。"
}

# 生成 Release Notes
generate_release_notes() {
    local manifest_file="$1"
    local output_file="$2"
    
    if [ ! -f "$manifest_file" ]; then 
        log_error "Manifest 文件 $manifest_file 不存在！"; 
        return 1
    fi
    
    log_info "正在生成 Release Notes..."
    local luci_apps
    luci_apps=$(grep -o 'luci-app-[^"]*' "$manifest_file" | sort -u | sed 's/^/- /' || true)
    
    # 获取环境变量
    local branch_name="${BRANCH_NAME:-unknown}"
    local chipset_name="${CHIPSET_NAME:-unknown}"
    local ubuntu_version="${UBUNTU_VERSION:-unknown}"
    
    cat << EOF > "$output_file"
# 🚀 OpenWrt 固件发布

本固件由 GitHub Actions 自动编译于 $(date '+%Y-%m-%d %H:%M:%S') (UTC+8)。

---

## 📦 编译信息

- **源码分支**: ${branch_name}
- **芯片架构**: ${chipset_name}
- **构建环境**: ${ubuntu_version}

---

## ✨ 成功编译的 LuCI 应用

 ${luci_apps}

---

## 📁 文件说明

每个附件的压缩包内包含固件、配置、清单和所有软件包。

---

## ⚠️ 重要提示

- 刷机前请务必备份。
- 本固件未集成任何第三方软件源。

Happy Hacking! 🎉
EOF
    log_success "Release Notes 生成于 $output_file"
}

# 列出第三方包
list_third_party_packages() {
    if [ ! -d "package/feeds" ]; then
        log_error "Feeds 目录不存在，请先运行 feeds install。"
        return 1
    fi
    find package/feeds -mindepth 1 -maxdepth 2 -type d -name "luci-app-*" -printf 'CONFIG_PACKAGE_%p=m\n' | sed 's|package/feeds/[^/]*/||'
}

# Git稀疏克隆函数
git_sparse_clone() {
    local branch="$1"
    local repourl="$2"
    shift 2
    
    log_info "稀疏克隆 $repourl (分支: $branch, 目录: $@)"
    
    # 创建临时目录
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # 克隆仓库
    if ! git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl"; then
        log_error "克隆仓库失败: $repourl"
        cd - && rm -rf "$temp_dir"
        return 1
    fi
    
    # 获取仓库名称
    local repodir
    repodir=$(echo "$repourl" | awk -F '/' '{print $(NF)}')
    cd "$repodir"
    
    # 设置稀疏检出
    if ! git sparse-checkout set "$@"; then
        log_error "设置稀疏检出失败: $@"
        cd - && rm -rf "$temp_dir"
        return 1
    fi
    
    # 移动文件到目标位置
    for dir in "$@"; do
        if [ -d "$dir" ]; then
            mv -f "$dir" "$PROJECT_ROOT/package/"
            log_info "已添加: $dir"
        else
            log_warning "目录不存在: $dir"
        fi
    done
    
    # 清理临时目录
    cd - && rm -rf "$temp_dir"
}
