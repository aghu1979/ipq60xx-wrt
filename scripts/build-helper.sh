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
    echo "OpenWrt 构建辅助脚本"
    echo ""
    echo "用法: $0 <命令> [参数...]"
    echo ""
    echo "可用命令:"
    echo "  get-devices <config_file>     从配置文件提取设备列表"
    echo "  select-device <config_file> <device_name> <chipset>  选择设备配置"
    echo "  generate-notes <manifest_file> <output_file>  生成 Release Notes"
    echo "  list-third-party-packages     列出第三方包"
    echo "  help                          显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 get-devices configs/ipq60xx.base.config"
    echo "  $0 select-device .config ax6000 ipq60xx"
    echo "  $0 generate-notes manifest release_notes.md"
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
            log_error "缺少配置文件参数"
            echo "用法: $0 get-devices <config_file>"
            exit 1
        fi
        
        # 检查配置文件是否存在
        if [ ! -f "$1" ]; then
            log_error "配置文件 $1 不存在！"
            echo "[]"
            exit 1
        fi
        
        log_info "正在从 $1 提取设备名..."
        
        # 使用正则表达式提取设备名
        # 匹配模式: CONFIG_TARGET_..._DEVICE_设备名=y 或 CONFIG_TARGET_DEVICE_..._DEVICE_设备名=y
        local devices
        devices=$(grep -E "^CONFIG_TARGET(_DEVICE)?_[a-zA-Z0-9_]+_DEVICE_[a-zA-Z0-9_-]+=y" "$1" | \
                 sed -E 's/^CONFIG_TARGET(_DEVICE)?_[a-zA-Z0-9_]+_DEVICE_([a-zA-Z0-9_-]+)=y$/\2/' | \
                 sort -u)
        
        if [ -z "$devices" ]; then
            log_warning "在 $1 中未找到任何设备"
            echo "[]"
            exit 0
        fi
        
        # 确保输出有效的JSON数组
        echo "$devices" | jq -R . | jq -s .
        ;;
        
    select-device)
        if [ $# -ne 3 ]; then
            log_error "参数数量不正确"
            echo "用法: $0 select-device <config_file> <device_name> <chipset>"
            exit 1
        fi
        select_device_config "$1" "$2" "$3"
        ;;
        
    generate-notes)
        if [ $# -ne 2 ]; then
            log_error "参数数量不正确"
            echo "用法: $0 generate-notes <manifest_file> <output_file>"
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
        log_error "未知命令 '$COMMAND'"
        echo "使用 '$0 help' 查看可用命令"
        exit 1
        ;;
esac
