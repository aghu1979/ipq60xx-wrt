#!/bin/bash

# 用户自定义脚本，用于加载第三方源和修改默认设置

# 阶段1: 在 feeds update 之前执行
pre_feeds() {
    source scripts/build-helper.sh
    log_info "执行 DIY: 加载第三方软件源..."
    # 示例: 添加一个第三方 feed
    # echo 'src-git custom_feed https://github.com/example/custom-feed.git' >> feeds.conf.default
    log_success "第三方软件源加载完成。"
}

# 阶段2: 在 feeds install 之后，编译之前执行
post_feeds() {
    source scripts/build-helper.sh
    log_info "执行 DIY: 修改默认路由器设置..."
    
    # 示例: 修改默认主机名
    # sed -i 's/OpenWrt/MyRouter/g' package/base-files/files/etc/config/system
    
    # 示例: 修改默认 LAN IP
    # sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/files/etc/config/network
    
    log_success "默认设置修改完成。"
}

# --- 主逻辑 ---
COMMAND=${1:-all}

# 在这里加载日志函数，以便在 diy.sh 中使用
source "$(dirname "$0")/build-helper.sh"

case "$COMMAND" in
    pre-feeds)
        pre_feeds
        ;;
    post-feeds)
        post_feeds
        ;;
    all)
        pre_feeds
        post_feeds
        ;;
    *)
        log_error "未知命令 '$COMMAND'"
        echo "可用命令: pre-feeds, post-feeds, all"
        exit 1
        ;;
esac

#!/usr/bin/env bash
# scripts/diy.sh - 在上游仓库目录下执行，添加/更新第三方包、修改默认配置等（已优化）
#!/bin/bash

# 设置错误退出
set -e

# 修改默认IP & 固件名称 & 编译署名
sed -i 's/192.168.1.1/192.168.111.1/g' package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='WRT'/g" package/base-files/files/bin/config_generate

# 移除要替换的包
rm -rf feeds/luci/applications/luci-app-appfilter
rm -rf feeds/luci/applications/luci-app-frpc
rm -rf feeds/luci/applications/luci-app-frps
rm -rf feeds/packages/net/open-app-filter
rm -rf feeds/packages/net/adguardhome
rm -rf feeds/packages/net/ariang
rm -rf feeds/packages/net/frp
rm -rf feeds/packages/lang/golang

# Git稀疏克隆，只克隆指定目录到本地
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../package
  cd .. && rm -rf $repodir
}

# Go & OpenList & ariang & frp & AdGuardHome & WolPlus & Lucky & OpenAppFilter & 集客无线AC控制器 & 雅典娜LED控制
git clone --depth=1 https://github.com/sbwml/packages_lang_golang   feeds/packages/lang/golang
git clone --depth=1 https://github.com/sbwml/luci-app-openlist2   package/openlist
git_sparse_clone ariang https://github.com/laipeng668/packages   net/ariang
git_sparse_clone frp https://github.com/laipeng668/packages   net/frp
mv -f package/frp feeds/packages/net/frp
git_sparse_clone frp https://github.com/laipeng668/luci   applications/luci-app-frpc applications/luci-app-frps
mv -f package/luci-app-frpc feeds/luci/applications/luci-app-frpc
mv -f package/luci-app-frps feeds/luci/applications/luci-app-frps
# git_sparse_clone master https://github.com/kenzok8/openwrt-packages   adguardhome luci-app-adguardhome
git_sparse_clone main https://github.com/VIKINGYFY/packages   luci-app-wolplus
git clone --depth=1 https://github.com/lwb1978/openwrt-gecoosac   package/openwrt-gecoosac
git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led   package/luci-app-athena-led
chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led package/luci-app-athena-led/root/usr/sbin/athena-led

# ====== Mary定制包 ======
git clone --depth=1 https://github.com/sirpdboy/luci-app-netspeedtest   package/netspeedtest
git clone --depth=1 https://github.com/sirpdboy/luci-app-partexp   package/luci-app-partexp
git clone --depth=1 https://github.com/sirpdboy/luci-app-taskplan   package/luci-app-taskplan
git clone --depth=1 https://github.com/tailscale/tailscale   package/tailscale
git clone --depth=1 https://github.com/gdy666/luci-app-lucky   package/luci-app-lucky
git clone --depth=1 https://github.com/destan19/OpenAppFilter.git   package/OpenAppFilter
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-momo   package/luci-app-momo
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki   package/nikki
git clone --depth=1 https://github.com/vernesong/OpenClash   package/OpenClash

# ====== 添加kenzok8软件源并且让它的优先级最低，也就是如果有软件包冲突，它的软件包会被其它软件源替代。 ======
git clone --depth=1 https://github.com/kenzok8/small-package   small8 

./scripts/feeds update -a
./scripts/feeds install -a
