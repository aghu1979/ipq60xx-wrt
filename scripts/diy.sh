#!/bin/bash

# 用户自定义脚本，用于加载第三方源和修改默认设置（改进版）
set -euo pipefail

# 在这里加载日志函数，以便在 diy.sh 中使用
source "$(dirname "$0")/build-helper.sh"

# === 配置 ===
# 默认的 OpenWrt 工作目录（在 workflow 中我们使用 /workdir/openwrt）
OWDIR=${OWDIR:-/workdir/openwrt}
WORKDIR=${GITHUB_WORKSPACE:-$(pwd)}

# 阶段1: 在 feeds update 之前执行
pre_feeds() {
    log_info "执行 DIY: 加载第三方软件源..."
    # 示例: 添加一个第三方 feed（示例，按需打开）
    # if ! grep -q 'src-git custom_feed' feeds.conf.default; then
    #   echo 'src-git custom_feed https://github.com/example/custom-feed.git' >> feeds.conf.default
    # fi
    log_success "第三方软件源加载完成。"
}

# 方便的稀疏克隆辅助（参数: branch repo_dir path... -> 会把 path 移到 package/ 下）
git_sparse_clone() {
  branch="$1"
  repourl="$2"
  shift 2
  paths=("$@")
  tmpdir=$(mktemp -d)
  git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl" "$tmpdir"
  pushd "$tmpdir" >/dev/null
  git sparse-checkout set "${paths[@]}"
  for p in "${paths[@]}"; do
    destdir="${p##*/}"
    # 将目录移动到 package 下(如果需要)
    mkdir -p "../../package"
    mv -f "$p" "../../package/" || true
  done
  popd >/dev/null
  rm -rf "$tmpdir"
}

# 阶段2: 在 feeds install 之后，编译之前执行
post_feeds() {
    log_info "执行 DIY: 修改默认路由器设置并添加第三方包..."
    # 确保在 openwrt 根目录下
    if [ -d "$OWDIR" ]; then
      cd "$OWDIR"
    else
      cd "$WORKDIR"
    fi

    # 修改默认主机名与 LAN
    if [ -f package/base-files/files/bin/config_generate ]; then
      sed -i 's/192.168.1.1/192.168.111.1/g' package/base-files/files/bin/config_generate || true
      sed -i "s/hostname='.*'/hostname='WRT'/g" package/base-files/files/bin/config_generate || true
    fi

    # 删除/替换要替换的包（幂等）
    rm -rf feeds/luci/applications/luci-app-appfilter || true
    rm -rf feeds/luci/applications/luci-app-frpc || true
    rm -rf feeds/luci/applications/luci-app-frps || true
    rm -rf feeds/packages/net/open-app-filter || true
    rm -rf feeds/packages/net/adguardhome || true
    rm -rf feeds/packages/net/ariang || true
    rm -rf feeds/packages/net/frp || true
    rm -rf feeds/packages/lang/golang || true

    # 使用幂等方式 clone 第三方包（只有在目标目录不存在时才克隆）
    clone_if_missing() {
      url="$1"
      dest="$2"
      branch="${3:-master}"
      if [ -d "$dest" ]; then
        log_info "目录已存在，跳过: $dest"
        return 0
      fi
      git clone --depth=1 -b "$branch" "$url" "$dest" || { log_warning "克隆失败: $url"; }
    }

    # 示例：将包克隆到 package 或 feeds 目录（按需调整）
    clone_if_missing https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang
    clone_if_missing https://github.com/sbwml/luci-app-openlist2 package/openlist
    # 使用 sparse clone 示例
    # git_sparse_clone main https://github.com/laipeng668/packages net/ariang

    # 更多第三方仓库（仅示例）
    clone_if_missing https://github.com/laipeng668/packages package/laipeng-packages
    clone_if_missing https://github.com/laipeng668/luci package/laipeng-luci

    # 添加 kenzo8 软件源（设置为低优先级的方式留给 feeds 的配置或 package Makefile 处理）
    clone_if_missing https://github.com/kenzok8/small-package small8

    # 更新 feeds 索引（如果需要）
    if [ -f ./scripts/feeds ]; then
      ./scripts/feeds update -a || true
      ./scripts/feeds install -a || true
    fi

    log_success "默认设置修改和第三方包准备完成。"
}

# --- 主逻辑 ---
COMMAND=${1:-all}

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
