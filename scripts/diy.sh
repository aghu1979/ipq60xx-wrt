#!/bin/bash
# scripts/diy.sh - 用户自定义脚本，用于加载第三方源和修改默认设置

# 设置错误退出
set -euo pipefail

# 加载函数库
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ==================== 配置变量 ====================
# 默认IP和主机名
readonly DEFAULT_LAN_IP="192.168.111.1"
readonly DEFAULT_HOSTNAME="WRT"

# 要移除的包列表
readonly PACKAGES_TO_REMOVE=(
    "feeds/luci/applications/luci-app-appfilter"
    "feeds/luci/applications/luci-app-frpc"
    "feeds/luci/applications/luci-app-frps"
    "feeds/packages/net/open-app-filter"
    "feeds/packages/net/adguardhome"
    "feeds/packages/net/ariang"
    "feeds/packages/net/frp"
    "feeds/packages/lang/golang"
)

# 第三方包仓库
readonly GOLANG_REPO="https://github.com/sbwml/packages_lang_golang"
readonly OPENLIST_REPO="https://github.com/sbwml/luci-app-openlist2"
readonly LAIPENG_PACKAGES_REPO="https://github.com/laipeng668/packages"
readonly LAIPENG_LUCI_REPO="https://github.com/laipeng668/luci"
readonly VIKINGYFY_PACKAGES_REPO="https://github.com/VIKINGYFY/packages"
readonly GECOOSAC_REPO="https://github.com/lwb1978/openwrt-gecoosac"
readonly ATHENA_LED_REPO="https://github.com/NONGFAH/luci-app-athena-led"
readonly KENZOK8_SMALL_REPO="https://github.com/kenzok8/small-package"

# Mary定制包列表
readonly MARY_PACKAGES=(
    "https://github.com/sirpdboy/luci-app-netspeedtest:package/netspeedtest"
    "https://github.com/sirpdboy/luci-app-partexp:package/luci-app-partexp"
    "https://github.com/sirpdboy/luci-app-taskplan:package/luci-app-taskplan"
    "https://github.com/tailscale/tailscale:package/tailscale"
    "https://github.com/gdy666/luci-app-lucky:package/luci-app-lucky"
    "https://github.com/destan19/OpenAppFilter.git:package/OpenAppFilter"
    "https://github.com/nikkinikki-org/OpenWrt-momo:package/luci-app-momo"
    "https://github.com/nikkinikki-org/OpenWrt-nikki:package/nikki"
    "https://github.com/vernesong/OpenClash:package/OpenClash"
)

# ==================== 函数定义 ====================
# 阶段1: 在 feeds update 之前执行
pre_feeds() {
    log_info "执行 DIY: 加载第三方软件源..."
    
    # 备份原始feeds.conf.default
    if [ -f "feeds.conf.default" ]; then
        cp feeds.conf.default feeds.conf.default.backup
        log_info "已备份原始feeds.conf.default"
    fi
    
    # 添加自定义feeds到feeds.conf.default
    echo "src-git custom_packages https://github.com/sbwml/packages_lang_golang.git;main" >> feeds.conf.default
    echo "src-git custom_luci https://github.com/sbwml/luci-app-openlist2.git;main" >> feeds.conf.default
    log_info "已添加自定义feeds源"
    log_info "当前feeds.conf.default内容:"
    cat feeds.conf.default
    
    log_success "第三方软件源加载完成。"
}

# 阶段2: 在 feeds install 之后，编译之前执行
post_feeds() {
    log_info "执行 DIY: 修改默认路由器设置..."
    
    # 示例: 修改默认主机名
    # sed -i 's/OpenWrt/MyRouter/g' package/base-files/files/etc/config/system
    
    # 示例: 修改默认 LAN IP
    # sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/files/etc/config/network
    
    log_success "默认设置修改完成。"
}

# 修改默认配置
modify_default_config() {
    log_info "修改默认IP和主机名..."
    sed -i "s/192.168.1.1/$DEFAULT_LAN_IP/g" package/base-files/files/bin/config_generate
    sed -i "s/hostname='.*'/hostname='$DEFAULT_HOSTNAME'/g" package/base-files/files/bin/config_generate
}

# 移除要替换的包
remove_packages() {
    log_info "移除要替换的包..."
    for package in "${PACKAGES_TO_REMOVE[@]}"; do
        if [ -d "$package" ]; then
            rm -rf "$package"
            log_info "已移除: $package"
        else
            log_warning "包不存在，跳过: $package"
        fi
    done
}

# 添加基础第三方包
add_basic_packages() {
    log_info "添加基础第三方包..."
    
    # Go语言支持
    if [ ! -d "feeds/packages/lang/golang" ]; then
        log_info "克隆 golang..."
        git clone --depth=1 "$GOLANG_REPO" feeds/packages/lang/golang
        if [ -d "feeds/packages/lang/golang" ]; then
            log_info "已添加: golang"
        else
            log_info "golang 已存在，跳过"
    fi
    
    # OpenList
    if [ ! -d "package/openlist" ]; then
        log_info "克隆 openlist..."
        git clone --depth=1 "$OPENLIST_REPO" package/openlist
        if [ -d "package/openlist" ]; then
            log_info "已添加: openlist"
        else
            log_info "openlist 已存在，跳过"
    fi
    
    # ariang
    if [ ! -d "feeds/packages/net/ariang" ]; then
        log_info "稀疏克隆 ariang..."
        git_sparse_clone ariang "$LAIPENG_PACKAGES_REPO" net/ariang
        if [ -d "feeds/packages/net/ariang" ]; then
            log_info "已添加: ariang"
        else
            log_info "ariang 已存在，跳过"
    fi
    
    # frp
    if [ ! -d "feeds/packages/net/frp" ]; then
        log_info "稀疏克隆 frp..."
        git_sparse_clone frp "$LAIPENG_PACKAGES_REPO" net/frp
        if [ -d "feeds/packages/net/frp" ]; then
            log_info "已添加: frp"
        else
            log_info "frp 已存在，跳过"
    fi
    
    # frpc/frps
    if [ ! -d "feeds/luci/applications/luci-app-frpc" ]; then
        log_info "稀疏克隆 frpc/frps..."
        git_sparse_clone frp "$LAIPENG_LUCI_REPO" applications/luci-app-frpc applications/luci-app-frps
        if [ -d "feeds/luci/applications/luci-app-frpc" ]; then
            log_info "已添加: frpc/frps"
        else
            log_info "frpc/frps 已存在，跳过"
    fi
    
    # WolPlus
    if [ ! -d "package/luci-app-wolplus" ]; then
        log_info "稀疏克隆 wolplus..."
        git_sparse_clone main "$VIKINGYFY_PACKAGES_REPO" luci-app-wolplus
        if [ -d "package/luci-app-wolplus" ]; then
            log_info "已添加: wolplus"
        else
            log_info "wolplus 已存在，跳过"
    fi
    
    # GecoosAC
    if [ ! -d "package/openwrt-gecoosac" ]; then
        log_info "克隆 gecoosac..."
        git clone --depth=1 "$GECOOSAC_REPO" package/openwrt-gecoosac
        if [ -d "package/openwrt-gecoosac" ]; then
            log_info "已添加: gecoosac"
        else
            log_info "gecoosac 已存在，跳过"
    fi
    
    # Athena LED
    if [ ! -d "package/luci-app-athena-led" ]; then
        log_info "克隆 athena-led..."
        git clone --depth=1 "$ATHENA_LED_REPO" package/luci-app-athena-led
        if [ -d "package/luci-app-athena-led" ]; then
            chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led package/luci-app-athena-led/root/usr/sbin/athena-led
            log_info "已添加: athena-led"
        else
            log_info "athena-led 已存在，跳过"
        fi
}

# 添加Mary定制包
add_mary_packages() {
    log_info "添加Mary定制包..."
    for package_url in "${MARY_PACKAGES[@]}"; do
        local url="${package_url%:*}"
        local target="${package_url#*:}"
        local package_name=$(basename "$target")
        
        if [ ! -d "$target" ]; then
            log_info "克隆 $url 到 $target"
            git clone --depth=1 "$url" "$target"
            if [ -d "$target" ]; then
                log_info "已添加: $package_name"
            else
                log_error "$package_name 克隆失败"
            fi
        else
            log_info "$package_name 已存在，跳过"
        fi
    done
}

# 添加kenzok8软件源
add_kenzok8_source() {
    log_info "添加kenzok8软件源..."
    if [ ! -d "small8" ]; then
        git clone --depth=1 "$KENZOK8_SMALL_REPO" small8 
        if [ -d "small8" ]; then
            log_info "已添加: kenzok8 small-package"
        else
            log_info "kenzok8 small-package 已存在，跳过"
    fi
}

# 更新和安装Feeds
update_feeds() {
    log_info "更新和安装Feeds..."
    
    # 清理旧的feeds
    log_info "清理旧的feeds..."
    rm -rf feeds/
    rm -rf package/feeds/
    
    # 初始化feeds
    log_info "初始化feeds..."
    ./scripts/feeds clean
    ./scripts/feeds uninstall -a
    
    # 更新feeds
    log_info "更新feeds..."
    ./scripts/feeds update -a
    
    # 安装feeds
    log_info "安装feeds..."
    ./scripts/feeds install -a
    
    log_success "Feeds更新和安装完成。"
}

# 执行实际的DIY操作
execute_diy() {
    log_info "开始执行DIY操作..."
    
    modify_default_config
    remove_packages
    add_basic_packages
    add_mary_packages
    add_kenzok8_source
    
    # 重新更新feeds以包含新添加的包
    log_info "重新更新feeds以包含新添加的包..."
    update_feeds
    
    log_success "DIY操作完成"
}

# ==================== 主逻辑 ====================
# 显示帮助信息
show_help() {
    echo "OpenWrt DIY 脚本"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "可用命令:"
    echo "  pre-feeds     执行第一阶段操作 (在 feeds update 之前)"
    echo "  post-feeds    执行第二阶段操作和DIY (在 feeds install 之后)"
    echo "  all           执行所有操作 (默认)"
    echo "  help          显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 pre-feeds"
    echo "  $0 post-feeds"
    echo "  $0 all"
}

# 处理命令
COMMAND="${1:-all}"

case "$COMMAND" in
    pre-feeds)
        pre_feeds
        ;;
    post-feeds)
        post_feeds
        execute_diy
        ;;
    all)
        pre_feeds
        post_feeds
        execute_diy
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
