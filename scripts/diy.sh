#!/bin/bash
# scripts/diy.sh

# 启用严格模式：遇到错误立即退出，未定义的变量视为错误
set -euo pipefail

# --- 主逻辑 ---
main() {
    # 接收从 workflow 传入的参数
    local branch_name="${1:-openwrt}"
    local soc_name="${2:-ipq60xx}"

    echo "=========================================="
    echo " DIY Script for OpenWrt"
    echo " Branch: ${branch_name}"
    echo " SoC:     ${soc_name}"
    echo "=========================================="

    # 步骤 1: 修改默认IP & 固件名称 & 编译署名
    echo "==> Step 1: Modifying default settings..."
    sed -i 's/192.168.1.1/192.168.111.1/g' package/base-files/files/bin/config_generate
    sed -i "s/hostname='.*'/hostname='WRT'/g" package/base-files/files/bin/config_generate
    sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ Built by Mary')/g" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js
    echo "✅ Default settings modified."

    # 步骤 2: 预删除官方软件源缓存
    echo "==> Step 2: Pre-deleting official package caches..."
    OFFICIAL_CACHE_PACKAGES=(
"package/feeds/packages/golang"
        # laipeng668定制包相关的官方缓存包
        "package/feeds/packages/golang"
        "package/feeds/packages/ariang"
        "package/feeds/packages/frp"
        "package/feeds/packages/adguardhome"
        "package/feeds/packages/wolplus"
        "package/feeds/packages/lucky"
        "package/feeds/packages/wechatpush"
        "package/feeds/packages/open-app-filter"
        "package/feeds/packages/gecoosac"
        "package/feeds/luci/luci-app-frpc"
        "package/feeds/luci/luci-app-frps"
        "package/feeds/luci/luci-app-adguardhome"
        "package/feeds/luci/luci-app-wolplus"
        "package/feeds/luci/luci-app-lucky"
        "package/feeds/luci/luci-app-wechatpush"
        "package/feeds/luci/luci-app-athena-led"

        # Mary定制包相关的官方缓存包
        "package/feeds/packages/netspeedtest"
        "package/feeds/packages/partexp"
        "package/feeds/packages/taskplan"
        "package/feeds/packages/tailscale"
        "package/feeds/packages/momo"
        "package/feeds/packages/nikki"
        "package/feeds/luci/luci-app-netspeedtest"
        "package/feeds/luci/luci-app-partexp"
        "package/feeds/luci/luci-app-taskplan"
        "package/feeds/luci/luci-app-tailscale"
        "package/feeds/luci/luci-app-momo"
        "package/feeds/luci/luci-app-nikki"
        "package/feeds/luci/luci-app-openclash"
    )

    for package in "${OFFICIAL_CACHE_PACKAGES[@]}"; do
        if [ -d "$package" ]; then
            rm -rf "$package"
            echo "已删除缓存包: $package"
        fi
    done

    # 步骤 3: 预删除feeds工作目录
    echo "==> Step 3: Pre-deleting feeds working directories..."
    FEEDS_WORK_PACKAGES=(
        # laipeng668定制包相关的feeds工作目录
        "feeds/packages/lang/golang"
        "feeds/packages/net/ariang"
        "feeds/packages/net/frp"
        "feeds/packages/net/adguardhome"
        "feeds/packages/net/wolplus"
        "feeds/packages/net/lucky"
        "feeds/packages/net/wechatpush"
        "feeds/packages/net/open-app-filter"
        "feeds/packages/net/gecoosac"
        "feeds/luci/applications/luci-app-frpc"
        "feeds/luci/applications/luci-app-frps"
        "feeds/luci/applications/luci-app-adguardhome"
        "feeds/luci/applications/luci-app-wolplus"
        "feeds/luci/applications/luci-app-lucky"
        "feeds/luci/applications/luci-app-wechatpush"
        "feeds/luci/applications/luci-app-athena-led"

        # Mary定制包相关的feeds工作目录
        "feeds/packages/net/netspeedtest"
        "feeds/packages/utils/partexp"
        "feeds/packages/utils/taskplan"
        "feeds/packages/net/tailscale"
        "feeds/packages/net/momo"
        "feeds/packages/net/nikki"
        "feeds/luci/applications/luci-app-netspeedtest"
        "feeds/luci/applications/luci-app-partexp"
        "feeds/luci/applications/luci-app-taskplan"
        "feeds/luci/applications/luci-app-tailscale"
        "feeds/luci/applications/luci-app-momo"
        "feeds/luci/applications/luci-app-nikki"
        "feeds/luci/applications/luci-app-openclash"
    )

    for package in "${FEEDS_WORK_PACKAGES[@]}"; do
        if [ -d "$package" ]; then
            rm -rf "$package"
            echo "已删除工作目录包: $package"
        fi
    done

    # 步骤 4: 克隆定制化软件包
    echo "==> Step 4: Cloning custom packages..."
    # laipeng668定制包
    git clone --depth=1 https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang
    git clone --depth=1 https://github.com/sbwml/luci-app-openlist2 package/openlist
    git clone --depth=1 https://github.com/laipeng668/packages.git feeds/packages/net/ariang
    git clone --depth=1 https://github.com/laipeng668/packages.git feeds/packages/net/frp
    git clone --depth=1 https://github.com/laipeng668/luci.git feeds/luci/applications/luci-app-frpc
    git clone --depth=1 https://github.com/laipeng668/luci.git feeds/luci/applications/luci-app-frps
    git clone --depth=1 https://github.com/kenzok8/openwrt-packages.git package/adguardhome
    git clone --depth=1 https://github.com/kenzok8/openwrt-packages.git package/luci-app-adguardhome
    git clone --depth=1 https://github.com/VIKINGYFY/packages.git feeds/luci/applications/luci-app-wolplus
    git clone --depth=1 https://github.com/tty228/luci-app-wechatpush.git package/luci-app-wechatpush
    git clone --depth=1 https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter
    git clone --depth=1 https://github.com/lwb1978/openwrt-gecoosac.git package/openwrt-gecoosac
    git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led.git package/luci-app-athena-led
    
    # Mary定制包
    git clone --depth=1 https://github.com/sirpdboy/luci-app-netspeedtest.git package/netspeedtest
    git clone --depth=1 https://github.com/sirpdboy/luci-app-partexp.git package/partexp
    git clone --depth=1 https://github.com/sirpdboy/luci-app-taskplan.git package/taskplan
    git clone --depth=1 https://github.com/tailscale/tailscale.git package/tailscale
    git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-momo.git package/momo
    git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki.git package/nikki
    git clone --depth=1 https://github.com/vernesong/OpenClash.git package/openclash

    # kenzok8软件源
    git clone --depth=1 https://github.com/kenzok8/small-package smpackage 


    # 设置权限
    chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led package/luci-app-athena-led/root/usr/sbin/athena-led
    
    echo "✅ Custom packages cloned."

    # 注意：feeds update 和 install 已移至 build.yml 中，以便利用缓存
    echo "==> DIY script finished successfully."
}

# 执行主函数，并传入所有参数
main "$@"
