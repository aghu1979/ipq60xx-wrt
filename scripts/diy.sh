#!/bin/bash
# scripts/diy.sh - 用户自定义脚本，用于加载第三方源和修改默认设置

# 设置错误退出
set -euo pipefail

# 加载日志函数
source "$(dirname "$0")/build-helper.sh"

# 阶段1: 在 feeds update 之前执行
pre_feeds() {
    log_info "执行 DIY: 加载第三方软件源..."
    # 示例: 添加一个第三方 feed
    # echo 'src-git custom_feed https://github.com/example/custom-feed.git' >> feeds.conf.default
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

# 执行实际的DIY操作
execute_diy() {
    log_info "开始执行DIY操作..."
    
    # 修改默认IP & 固件名称 & 编译署名
    log_info "修改默认IP和主机名..."
    sed -i 's/192.168.1.1/192.168.111.1/g' package/base-files/files/bin/config_generate
    sed -i "s/hostname='.*'/hostname='WRT'/g" package/base-files/files/bin/config_generate

    # 移除要替换的包
    log_info "移除要替换的包..."
    PACKAGES_TO_REMOVE=(
        "feeds/luci/applications/luci-app-appfilter"
        "feeds/luci/applications/luci-app-frpc"
        "feeds/luci/applications/luci-app-frps"
        "feeds/packages/net/open-app-filter"
        "feeds/packages/net/adguardhome"
        "feeds/packages/net/ariang"
        "feeds/packages/net/frp"
        "feeds/packages/lang/golang"
    )

    for package in "${PACKAGES_TO_REMOVE[@]}"; do
        if [ -d "$package" ]; then
            rm -rf "$package"
            log_info "已移除: $package"
        else
            log_warning "包不存在，跳过: $package"
        fi
    done

    # Git稀疏克隆，只克隆指定目录到本地
    function git_sparse_clone() {
        local branch="$1"
        local repourl="$2"
        shift 2
        
        log_info "稀疏克隆 $repourl (分支: $branch, 目录: $@)"
        
        # 创建临时目录
        local temp_dir=$(mktemp -d)
        cd "$temp_dir"
        
        # 克隆仓库
        if ! git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl"; then
            log_error "克隆仓库失败: $repourl"
            cd - && rm -rf "$temp_dir"
            return 1
        fi
        
        # 获取仓库名称
        local repodir=$(echo "$repourl" | awk -F '/' '{print $(NF)}')
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
                mv -f "$dir" "$GITHUB_WORKSPACE/package/"
                log_info "已添加: $dir"
            else
                log_warning "目录不存在: $dir"
            fi
        done
        
        # 清理临时目录
        cd - && rm -rf "$temp_dir"
    }

    # 添加第三方包
    log_info "添加第三方包..."
    # Go & OpenList & ariang & frp & AdGuardHome & WolPlus & Lucky & OpenAppFilter & 集客无线AC控制器 & 雅典娜LED控制
    git clone --depth=1 https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang
    git clone --depth=1 https://github.com/sbwml/luci-app-openlist2 package/openlist
    git_sparse_clone ariang https://github.com/laipeng668/packages net/ariang
    git_sparse_clone frp https://github.com/laipeng668/packages net/frp
    mv -f package/frp feeds/packages/net/frp
    git_sparse_clone frp https://github.com/laipeng668/luci applications/luci-app-frpc applications/luci-app-frps
    mv -f package/luci-app-frpc feeds/luci/applications/luci-app-frpc
    mv -f package/luci-app-frps feeds/luci/applications/luci-app-frps
    git_sparse_clone main https://github.com/VIKINGYFY/packages luci-app-wolplus
    git clone --depth=1 https://github.com/lwb1978/openwrt-gecoosac package/openwrt-gecoosac
    git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led
    chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led package/luci-app-athena-led/root/usr/sbin/athena-led

    # Mary定制包
    log_info "添加Mary定制包..."
    MARY_PACKAGES=(
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

    for package_url in "${MARY_PACKAGES[@]}"; do
        url="${package_url%:*}"
        target="${package_url#*:}"
        log_info "克隆 $url 到 $target"
        git clone --depth=1 "$url" "$target"
    done

    # 添加kenzok8软件源
    log_info "添加kenzok8软件源..."
    git clone --depth=1 https://github.com/kenzok8/small-package small8 

    # 更新和安装Feeds
    log_info "更新和安装Feeds..."
    ./scripts/feeds update -a
    ./scripts/feeds install -a
    
    log_success "DIY操作完成"
}

# --- 主逻辑 ---
COMMAND=${1:-all}

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
    *)
        log_error "未知命令 '$COMMAND'"
        echo "可用命令: pre-feeds, post-feeds, all"
        exit 1
        ;;
esac
