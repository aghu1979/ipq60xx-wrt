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

# 1. 设置默认IP地址
echo "🌐 设置默认管理IP地址为 192.168.111.1"
sed -i 's/192.168.1.1/192.168.111.1/g' package/base-files/files/bin/config_generate

# 2. 设置默认WiFi名称和密码
echo "📶 设置默认WiFi名称和密码"
sed -i 's/ssid=OpenWrt/ssid=OpenWrt/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh
sed -i 's/key=12345678/key=12345678/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh

# 3. 添加第三方源
echo "📦 添加第三方源"

# 创建自定义源文件
cat > feeds.conf.default << EOF
src-git packages https://github.com/openwrt/packages.git;main
src-git luci https://github.com/openwrt/luci.git;main
src-git routing https://github.com/openwrt/routing.git;main
src-git telephony https://github.com/openwrt/telephony.git;main
src-git management https://github.com/openwrt/packages.git;main
EOF

# 4. 添加自定义软件包源
echo "🔧 添加自定义软件包源"

# 创建自定义软件包目录
mkdir -p package/custom

# 添加示例自定义软件包
cat > package/custom/README.md << EOF
# 自定义软件包目录

在此目录下可以添加自定义软件包
EOF

# 5. 修改默认主题
echo "🎨 设置默认主题为Argon"
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# 6. 添加自定义配置
echo "⚙️ 添加自定义配置"

# 添加自定义系统配置
cat > package/custom/custom-system/files/etc/sysctl.conf << EOF
# 自定义系统配置
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOF

# 7. 添加自定义初始化脚本
echo "🚀 添加自定义初始化脚本"

mkdir -p package/custom/custom-system/files/etc/init.d
cat > package/custom/custom-system/files/etc/init.d/99-custom-init << EOF
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
    
    # 重启网络服务
    /etc/init.d/network restart
    /etc/init.d/system restart
    
    echo "自定义初始化脚本执行完成"
}
EOF

chmod +x package/custom/custom-system/files/etc/init.d/99-custom-init

# 8. 添加自定义软件包Makefile
echo "📦 创建自定义软件包Makefile"

cat > package/custom/custom-system/Makefile << EOF
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
