#!/bin/bash

# DIY脚本：配置第三方源及设备初始管理IP/密码
# 参数: $1 = OpenWrt源码路径

OPENWRT_PATH="$1"

if [ -z "$OPENWRT_PATH" ]; then
  echo "❌ 错误: 未提供OpenWrt源码路径"
  exit 1
fi

echo "🛠️ 开始执行DIY脚本..."

# 进入源码目录
cd "$OPENWRT_PATH" || exit 1

# 1. 修改默认IP、主机名、编译署名和WiFi设置
echo "🌐 修改默认IP、主机名、编译署名和WiFi设置"
sed -i 's/192.168.1.1/192.168.111.1/g' package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='OpenWrt'/g" package/base-files/files/bin/config_generate
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ Built by Mary')/g" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js

# 2. 调整NSS驱动q6_region内存区域预留大小（可选，默认注释）
echo "🔧 NSS驱动内存预留配置（已注释，如需启用请取消注释）"
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x01000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x02000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x04000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x06000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi

# 3. 移除要替换的包
echo "🗑️ 移除要替换的包"
PACKAGES_TO_REMOVE=(
    "feeds/luci/applications/luci-app-wechatpush"
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
        echo "已移除: $package"
    else
        echo "包不存在，跳过: $package"
    fi
done

# 4. Git稀疏克隆函数
echo "📥 定义Git稀疏克隆函数"
git_sparse_clone() {
    branch="$1" 
    repourl="$2" 
    shift 2
    
    echo "克隆仓库: $repourl (分支: $branch, 目录: $@)"
    git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
    repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
    cd $repodir && git sparse-checkout set $@
    mv -f $@ ../package/
    cd .. && rm -rf $repodir
    echo "完成克隆: $repourl"
}

# 5. 定义包安装函数
echo "📦 定义包安装函数"
install_package() {
    local name="$1"
    local url="$2"
    local target="$3"
    local branch="${4:-master}"
    
    echo "安装包: $name"
    if [ -d "package/$target" ]; then
        echo "包已存在，跳过: $target"
        return
    fi
    
    if [[ "$url" == *"@"* ]]; then
        # 稀疏克隆
        local repo_url="${url%@*}"
        local sparse_path="${url#*@}"
        git_sparse_clone "$branch" "$repo_url" "$sparse_path"
    else
        # 完整克隆
        git clone --depth=1 -b "$branch" "$url" "package/$target"
    fi
    echo "完成安装: $name"
}

# 6. laipeng668定制包列表
echo "🎁 laipeng668定制包列表"
declare -A LAIPENG_PACKAGES=(
    ["golang"]="https://github.com/sbwml/packages_lang_golang|feeds/packages/lang/golang"
    ["openlist"]="https://github.com/sbwml/luci-app-openlist2|package/openlist"
    ["ariang"]="https://github.com/laipeng668/packages@net/ariang|package/ariang"
    ["frp"]="https://github.com/laipeng668/packages@net/frp|package/frp"
    ["frpc"]="https://github.com/laipeng668/luci@applications/luci-app-frpc|package/luci-app-frpc"
    ["frps"]="https://github.com/laipeng668/luci@applications/luci-app-frps|package/luci-app-frps"
    ["adguardhome"]="https://github.com/kenzok8/openwrt-packages@adguardhome|package/adguardhome"
    ["luci-app-adguardhome"]="https://github.com/kenzok8/openwrt-packages@luci-app-adguardhome|package/luci-app-adguardhome"
    ["wolplus"]="https://github.com/VIKINGYFY/packages@luci-app-wolplus|package/wolplus"
    ["lucky"]="https://github.com/gdy666/luci-app-lucky|package/lucky"
    ["wechatpush"]="https://github.com/tty228/luci-app-wechatpush|package/wechatpush"
    ["openappfilter"]="https://github.com/destan19/OpenAppFilter.git|package/openappfilter"
    ["gecoosac"]="https://github.com/lwb1978/openwrt-gecoosac|package/gecoosac"
    ["athena-led"]="https://github.com/NONGFAH/luci-app-athena-led|package/athena-led"
)

# 7. Mary定制包列表（已移除与laipeng668重复的包）
echo "🎁 Mary定制包列表"
declare -A MARY_PACKAGES=(
    ["netspeedtest"]="https://github.com/sirpdboy/luci-app-netspeedtest|package/netspeedtest"
    ["partexp"]="https://github.com/sirpdboy/luci-app-partexp|package/partexp"
    ["taskplan"]="https://github.com/sirpdboy/luci-app-taskplan|package/taskplan"
    ["tailscale"]="https://github.com/tailscale/tailscale|package/tailscale"
    ["momo"]="https://github.com/nikkinikki-org/OpenWrt-momo|package/momo"
    ["nikki"]="https://github.com/nikkinikki-org/OpenWrt-nikki|package/nikki"
    ["openclash"]="https://github.com/vernesong/OpenClash|package/openclash"
)

# 8. 安装laipeng668定制包
echo "📦 安装laipeng668定制包"
for package_name in "${!LAIPENG_PACKAGES[@]}"; do
    package_info="${LAIPENG_PACKAGES[$package_name]}"
    url="${package_info%|*}"
    target="${package_info#*|}"
    
    # 特殊处理需要移动到feeds的包
    case "$package_name" in
        "golang")
            install_package "$package_name" "$url" "$target"
            ;;
        "frp")
            install_package "$package_name" "$url" "$target"
            if [ -d "package/frp" ]; then
                mv -f package/frp feeds/packages/net/frp
            fi
            ;;
        "frpc"|"frps")
            install_package "$package_name" "$url" "$target"
            if [ -d "package/luci-app-frpc" ]; then
                mv -f package/luci-app-frpc feeds/luci/applications/luci-app-frpc
            fi
            if [ -d "package/luci-app-frps" ]; then
                mv -f package/luci-app-frps feeds/luci/applications/luci-app-frps
            fi
            ;;
        *)
            install_package "$package_name" "$url" "$target"
            ;;
    esac
done

# 9. 安装Mary定制包
echo "📦 安装Mary定制包"
for package_name in "${!MARY_PACKAGES[@]}"; do
    package_info="${MARY_PACKAGES[$package_name]}"
    url="${package_info%|*}"
    target="${package_info#*|}"
    install_package "$package_name" "$url" "$target"
done

# 10. 设置特殊权限
echo "🔐 设置特殊权限"
if [ -d "package/athena-led" ]; then
    chmod +x package/athena-led/root/etc/init.d/athena_led
    chmod +x package/athena-led/root/usr/sbin/athena-led
fi

# 11. 添加kenzok8软件源（优先级最低）
echo "🔗 添加kenzok8软件源（优先级最低）"
git clone --depth=1 https://github.com/kenzok8/small-package package/small-package

# 12. 更新和安装Feeds
echo "🔄 更新和安装Feeds"
./scripts/feeds update -a
./scripts/feeds install -a

# 13. 添加自定义系统配置
echo "⚙️ 添加自定义系统配置"
mkdir -p package/custom-system/files/etc
cat > package/custom-system/files/etc/sysctl.conf << EOF
# 自定义系统配置
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOF

# 14. 添加自定义初始化脚本
echo "🚀 添加自定义初始化脚本"
mkdir -p package/custom-system/files/etc/init.d
cat > package/custom-system/files/etc/init.d/99-custom-init << EOF
#!/bin/sh /etc/rc.common

START=99

start() {
    # 自定义初始化脚本
    echo "执行自定义初始化脚本..."
    
    # 设置时区
    uci set system.@system[0].timezone='CST-8'
    uci set system.@system[0].zonename='Asia/Shanghai'
    uci commit system
    
    # 设置NTP服务器
    uci delete system.ntp.server
    uci add_list system.ntp.server='0.openwrt.pool.ntp.org'
    uci add_list system.ntp.server='1.openwrt.pool.ntp.org'
    uci add_list system.ntp.server='2.openwrt.pool.ntp.org'
    uci add_list system.ntp.server='3.openwrt.pool.ntp.org'
    uci commit system
    
    # 设置WiFi配置（支持多频段）
    # 检测并配置所有WiFi设备
    wifi_count=0
    for wifi_device in \$(uci show wireless | grep "wifi-device" | cut -d. -f2 | cut -d= -f1); do
        echo "检测到WiFi设备: \$wifi_device"
        
        # 获取对应的wifi-iface
        wifi_iface=\$(uci show wireless | grep "wifi-iface" | grep "device='\$wifi_device'" | head -1 | cut -d. -f2 | cut -d= -f1)
        if [ -n "\$wifi_iface" ]; then
            echo "配置WiFi接口: \$wifi_iface"
            
            # 根据频段设置不同的SSID
            hwmode=\$(uci get wireless.\$wifi_device.hwmode 2>/dev/null || echo "unknown")
            case "\$hwmode" in
                "11g"|"11b")
                    ssid="OpenWrt-2.4G"
                    ;;
                "11a")
                    # 检测是否为5.8GHz
                    channel=\$(uci get wireless.\$wifi_device.channel 2>/dev/null || echo "0")
                    if [ "\$channel" -gt 149 ] 2>/dev/null; then
                        ssid="OpenWrt-5.8G"
                    else
                        ssid="OpenWrt-5.2G"
                    fi
                    ;;
                *)
                    ssid="OpenWrt"
                    ;;
            esac
            
            # 设置SSID和空密码
            uci set wireless.\$wifi_iface.ssid="\$ssid"
            uci set wireless.\$wifi_iface.key=""
            uci set wireless.\$wifi_iface.encryption="none"
            uci commit wireless
            
            wifi_count=\$((wifi_count + 1))
        fi
    done
    
    # 启用WiFi
    uci set wireless.@wifi-device[0].disabled=0 2>/dev/null
    uci set wireless.@wifi-device[1].disabled=0 2>/dev/null
    uci commit wireless
    
    # 重启网络服务
    /etc/init.d/network restart
    /etc/init.d/system restart
    
    echo "自定义初始化脚本执行完成，已配置 \$wifi_count 个WiFi设备"
}
EOF

chmod +x package/custom-system/files/etc/init.d/99-custom-init

# 15. 添加自定义软件包Makefile
echo "📦 创建自定义软件包Makefile"
cat > package/custom-system/Makefile << EOF
#
# Copyright (C) 2023 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include \$(TOPDIR)/rules.mk

PKG_NAME:=custom-system
PKG_VERSION:=1.0
PKG_RELEASE:=1

include \$(INCLUDE_DIR)/package.mk

define Package/custom-system
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Custom system settings
  DEPENDS:=+luci
endef

define Package/custom-system/description
  This package contains custom system settings and scripts.
endef

define Build/Compile
endef

define Package/custom-system/install
    \$(INSTALL_DIR) \$(1)/etc
    \$(INSTALL_DATA) ./files/etc/sysctl.conf \$(1)/etc/
    \$(INSTALL_DIR) \$(1)/etc/init.d
    \$(INSTALL_BIN) ./files/etc/init.d/99-custom-init \$(1)/etc/init.d/
endef

\$(eval \$(call BuildPackage,custom-system))
EOF

echo "✅ DIY脚本执行完成"
