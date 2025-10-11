#!/usr/bin/env bash
# scripts/script.sh - 在上游仓库目录下执行，添加/更新第三方包、修改默认配置等（已优化）
# 说明：
#  1. build.sh 会在克隆上游仓库并切换到 UPSTREAM_DIR 后执行此脚本（即此脚本的当前目录为上游仓库根）
#  2. 日志会写到 GITHUB_WORKSPACE/logs/script.log（build.sh 会设置环境变量 LOG_DIR/LOG_FILE）
set -euo pipefail
IFS=$'\n\t'

LOG_DIR="${LOG_DIR:-logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/script.log}"
ERR_LOG="${ERR_LOG:-$LOG_DIR/script_error.log}"

mkdir -p "$LOG_DIR"
touch "$LOG_FILE" "$ERR_LOG"

log() { echo "[$(date '+%F %T')] [INFO] $*" | tee -a "$LOG_FILE"; }
warn() { echo "[$(date '+%F %T')] [WARN] $*" | tee -a "$LOG_FILE"; }
err() { echo "[$(date '+%F %T')] [ERROR] $*" | tee -a "$LOG_FILE"; echo "$*" >> "$ERR_LOG"; }

trap 'err "脚本意外退出（line:$LINENO）"; exit 1' ERR

safe_exec() {
  echo "[$(date '+%F %T')] CMD: $*" | tee -a "$LOG_FILE"
  if ! "$@" >> "$LOG_FILE" 2>&1; then
    err "命令失败: $*"
    return 1
  fi
  return 0
}

# Ensure we are inside a git repository (upstream)
if [ ! -d .git ]; then
  warn "当前目录不是 git 仓库（预期在上游仓库根），继续执行但某些操作可能失败"
fi

main() {
  log "script.sh: 开始（当前目录: $(pwd)）"

  # 修改默认 IP 与主机名（如有）
  if [ -f package/base-files/files/bin/config_generate ]; then
    safe_exec sed -i 's/192.168.1.1/192.168.111.1/g' package/base-files/files/bin/config_generate || true
    safe_exec sed -i "s/hostname='.*'/hostname='WRT'/g" package/base-files/files/bin/config_generate || true
    log "修改默认 IP 与主机名（如存在 config_generate）"
  else
    warn "未检测到 package/base-files/files/bin/config_generate，跳过系统默认修改"
  fi

  # 示例：克隆或更新常用第三方包源（已做容错）
  if [ ! -d package/netspeedtest ]; then
    safe_exec git clone --depth=1 https://github.com/sirpdboy/luci-app-netspeedtest package/netspeedtest || warn "克隆 netspeedtest 失败"
  else
    log "package/netspeedtest 已存在，跳过"
  fi

  if [ ! -d small8 ]; then
    safe_exec git clone --depth=1 https://github.com/kenzok8/small-package small8 || warn "克隆 small-package 失败"
  else
    log "small8 已存在，跳过"
  fi

  # 这里可添加更多包的克隆或移动逻辑，保持幂等
  log "script.sh: 完成"
}

main "$@"
