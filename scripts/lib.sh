#!/bin/bash

# OpenWrt DIY 脚本
# 用于处理 OpenWrt 构建过程中的自定义操作

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
    local message="$1"
    echo -e "${COLOR_BLUE}[INFO]${COLOR_NC} $message" | tee -a "${LOG_FILE}" >&2
}

log_success() { 
    local message="$1"
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_NC} $message" | tee -a "${LOG_FILE}" >&2
}

log_warning() { 
    local message="$1"
    echo -e "${COLOR_YELLOW}[WARNING]${COLOR_NC} $message" | tee -a "${LOG_FILE}" >&2
}

log_error() { 
    local message="$1"
    echo -e "${COLOR_RED}[ERROR]${COLOR_NC} $message" | tee -a "${LOG_FILE}" >&2
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
             grep -v "^ROOTFS$" | \  # 过滤掉ROOTFS
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
    
    # 注释掉所有设备配置
    sed -i 's/^CONFIG_TARGET(_DEVICE)\?_[a-zA-Z0-9_]\+_DEVICE_[a-zA-Z0-9_-]\+=y/# & is not set/' "$config_file"
    
    # 启用指定设备配置
    # 匹配两种可能的格式
    sed -i "s/^# CONFIG_TARGET(_DEVICE)\?_[a-zA-Z0-9_]\+_DEVICE_${device_name}=y/CONFIG_TARGET_DEVICE_${chipset}_${device_name}=y/" "$config_file"
    sed -i "s/^# CONFIG_TARGET(_DEVICE)\?_[a-zA-Z0-9_]\+_DEVICE_${device_name}=y/CONFIG_TARGET_${chipset}_${device_name}=y/" "$config_file"
    
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
    
    # 获取环境变量，设置默认值
    local branch_name="${BRANCH_NAME:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')}"
    local chipset_name="${CHIPSET_NAME:-${{ github.event.inputs.chipset || 'unknown' }}}"
    local ubuntu_version="${UBUNTU_VERSION:-${{ runner.os || 'unknown' }}}"
    local build_date="$(date '+%Y-%m-%d %H:%M:%S') (UTC+8)"
    
    cat << EOF > "$output_file"
# 🚀 OpenWrt 固件发布

本固件由 GitHub Actions 自动编译于 $build_date。

---

## 📦 编译信息

- **源码分支**: $branch_name
- **芯片架构**: $chipset_name
- **构建环境**: $ubuntu_version

---

## ✨ 成功编译的 LuCI 应用

 $luci_apps

---

## 📁 文件说明

每个附件的压缩包内包含：
- 固件文件 (.bin 文件)
- 配置文件 (.config)
- 构建信息 (config.buildinfo)
- 软件清单 (manifest)
- 构建日志 (build-*.log)
- 所有软件包 (packages.tar.gz)

---

## ⚠️ 重要提示

- 刷机前请务必备份重要数据
- 本固件已集成以下第三方应用：
  - OpenClash
  - Tailscale
  - Lucky
  - Athena LED控制
  - 网络速度测试
  - 分区扩展
  - 任务计划
  - 更多...

---

## 🔧️ 编译信息

- **构建ID**: ${{ github.run_id }}
- **提交哈希**: ${{ github.sha }}
- **构建时间**: $build_date

Happy Hacking! 🎉
EOF
    log_success "Release Notes 生成于 $output_file"
}

# 列出第三方包
list_third_party_packages() {
    log_info "检查 package/feeds 目录..." >&2
    if [ ! -d "package/feeds" ]; then
        log_error "Feeds 目录不存在，请先运行 feeds install。" >&2
        return 1
    fi
    
    log_info "列出 package/feeds 目录内容:" >&2
    ls -la package/feeds/ >&2
    
    log_info "查找所有 luci-app-* 目录:" >&2
    find package/feeds -name "luci-app-*" -type d >&2
    
    log_info "提取第三方包配置:" >&2
    local packages
    packages=$(find package/feeds -mindepth 1 -maxdepth 2 -type d -name "luci-app-*" -printf 'CONFIG_PACKAGE_%p=m\n' | sed 's|package/feeds/[^/]*/||' 2>/dev/null)
    
    # 同时查找package目录下的第三方包
    local more_packages
    more_packages=$(find package -maxdepth 1 -type d -name "luci-app-*" -not -path "package/feeds/*" -printf 'CONFIG_PACKAGE_%p=m\n' 2>/dev/null)
    
    if [ -n "$packages" ] || [ -n "$more_packages" ]; then
        if [ -n "$packages" ]; then
            log_info "从package/feeds找到的第三方包:" >&2
            echo "$packages" >&2
        fi
        if [ -n "$more_packages" ]; then
            log_info "从package根目录找到的第三方包:" >&2
            echo "$more_packages" >&2
        fi
    else
        log_warning "未找到任何第三方包" >&2
    fi
    
    # 合并并返回所有包
    echo -e "${packages}\n${more_packages}" | grep -v '^$'
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

# ==================== DIY 功能函数 ====================

# pre-feeds 阶段：在更新feeds之前执行
pre_feeds() {
    log_info "执行 pre-feeds 阶段操作..."
    
    # 备份原始feeds配置
    if [ -f "feeds.conf.default" ]; then
        cp feeds.conf.default feeds.conf.default.backup
        log_info "已备份原始feeds配置文件"
    fi
    
    # 添加第三方feeds
    cat >> feeds.conf.default << EOF

# 第三方feeds
src-git lienol https://github.com/Lienol/openwrt-package
src-git small https://github.com/kenzok8/small
EOF
    
    log_success "pre-feeds 阶段完成"
}

# post-feeds 阶段：在更新feeds之后执行
post_feeds() {
    log_info "执行 post-feeds 阶段操作..."
    
    # 这里可以添加feeds更新后的自定义操作
    # 例如：修改某些软件包的配置
    
    log_success "post-feeds 阶段完成"
}

# ==================== 主程序 ====================
main() {
    local command="${1:-}"
    
    case "$command" in
        "pre-feeds")
            pre_feeds
            ;;
        "post-feeds")
            post_feeds
            ;;
        "generate-notes")
            if [ $# -lt 3 ]; then
                log_error "用法: $0 generate-notes <manifest_file> <output_file>"
                exit 1
            fi
            generate_release_notes "$2" "$3"
            ;;
        "get-devices")
            if [ $# -lt 2 ]; then
                log_error "用法: $0 get-devices <config_file>"
                exit 1
            fi
            get_devices_from_config "$2"
            ;;
        "select-device")
            if [ $# -lt 4 ]; then
                log_error "用法: $0 select-device <config_file> <device_name> <chipset>"
                exit 1
            fi
            select_device_config "$2" "$3" "$4"
            ;;
        "list-packages")
            list_third_party_packages
            ;;
        *)
            log_error "未知命令: $command"
            log_error "可用命令: pre-feeds, post-feeds, generate-notes, get-devices, select-device, list-packages"
            exit 1
            ;;
    esac
}

# 执行主程序
main "$@"
