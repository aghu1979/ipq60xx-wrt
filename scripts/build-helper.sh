#!/bin/bash

# OpenWrt 构建辅助脚本
# 用于直接执行，处理构建相关任务

# 设置错误处理
set -euo pipefail

# 加载函数库
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ==================== 主逻辑 ====================
# 显示帮助信息
show_help() {
    echo "OpenWrt 构建辅助脚本" >&2
    echo "" >&2
    echo "用法: $0 <命令> [参数...]" >&2
    echo "" >&2
    echo "可用命令:" >&2
    echo "  get-devices <config_file>     从配置文件提取设备列表" >&2
    echo "  select-device <config_file> <device_name> <chipset>  选择设备配置" >&2
    echo "  generate-notes <manifest_file> <output_file> 生成 Release Notes" >&2
    echo "  list-third-party-packages     列出第三方包" >&2
    echo "  help                          显示此帮助信息" >&2
    echo "" >&2
    echo "示例:" >&2
    echo "  $0 get-devices configs/ipq60xx.base.config" >&2
    echo "  $0 select-device .config ax6000 ipq60xx" >&2
    echo "  $0 generate-notes manifest release_notes.md" >&2
}

# 检查参数
if [ $# -eq 0 ]; then
    show_help
    exit 1
fi

# 处理命令
COMMAND="$1"
shift

case "$COMMAND" in
    get-devices)
        if [ $# -eq 0 ]; then
            log_error "缺少配置文件参数" >&2
            echo "用法: $0 get-devices <config_file>" >&2
            exit 1
        fi
        
        # 检查配置文件是否存在
        if [ ! -f "$1" ]; then
            log_error "配置文件 $1 不存在！" >&2
            echo "[]"
            exit 1
        fi
        
        # 静默模式，不输出日志到stdout
        log_info "正在从 $1 提取设备名..." >&2
        
        # 使用正则表达式提取设备名
        # 匹配模式: CONFIG_TARGET_..._DEVICE_设备名=y 或 CONFIG_TARGET_DEVICE_..._DEVICE_设备名=y
        log_info "使用原始正则匹配..." >&2
        devices=$(grep -E "^CONFIG_TARGET(_DEVICE)?_[a-zA-Z0-9_]+_DEVICE_[a-zA-Z0-9_-]+=y" "$1" | \
                 sed -E 's/^CONFIG_TARGET(_DEVICE)?_[a-zA-Z0-9_]+_DEVICE_([a-zA-Z0-9_-]+)=y$/\2/' | \
                 grep -v "^ROOTFS$" | \
                 sort -u)
        
        # 如果原始正则没有匹配到，尝试更宽松的匹配
        if [ -z "$devices" ]; then
            log_info "原始正则未匹配到，尝试宽松匹配..." >&2
            devices=$(grep -E "CONFIG_TARGET.*DEVICE.*=y" "$1" | \
                     sed -E 's/^.*DEVICE_([a-zA-Z0-9_-]+)=y$/\1/' | \
                     grep -v "^ROOTFS$" | \
                     sort -u)
        fi
        
        # 如果还是没有匹配到，尝试更简单的匹配
        if [ -z "$devices" ]; then
            log_info "宽松匹配也未匹配到，尝试简单匹配..." >&2
            devices=$(grep -E "DEVICE_[a-zA-Z0-9_-]+=" "$1" | \
                     sed -E 's/^.*DEVICE_([a-zA-Z0-9_-]+)=.*$/\1/' | \
                     grep -v "^ROOTFS$" | \
                     sort -u)
        fi
        
        log_info "提取到的设备名: $devices" >&2
        
        if [ -z "$devices" ]; then
            log_warning "在 $1 中未找到任何设备" >&2
            echo "[]"
            exit 0
        fi
        
        # 确保输出有效的JSON数组，只输出JSON到stdout
        echo "$devices" | jq -R . | jq -s .
        ;;
        
    select-device)
        if [ $# -ne 3 ]; then
            log_error "参数数量不正确" >&2
            echo "用法: $0 select-device <config_file> <device_name> <chipset>" >&2
            exit 1
        fi
        select_device_config "$1" "$2" "$3"
        ;;
        
    generate-notes)
        if [ $# -ne 2 ]; then
            log_error "参数数量不正确" >&2
            echo "用法: $0 generate-notes <manifest_file> <output_file>" >&2
            exit 1
        fi
        generate_release_notes "$1" "$2"
        ;;
        
    list-third-party-packages)
        list_third_party_packages
        ;;
        
    help|--help|-h)
        show_help
        ;;
        
    *)
        log_error "未知命令 '$COMMAND'" >&2
        echo "使用 '$0 help' 查看可用命令" >&2
        exit 1
        ;;
esac
