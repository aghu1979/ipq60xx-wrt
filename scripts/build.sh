#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# main build script for GitHub Actions
# 功能：
#  - 克隆上游 openwrt/immortalwrt/libwrt 仓库（公开）
#  - 合并 config（chip_base + repo_base + Pro/Max/Ultra），合并规则为后优先（软件包配置 > 分支配置 > 芯片配置）
#  - 按构建顺序 Ultra -> Max -> Pro 依次构建（单 job 内循环设备）
#  - 提取设备名并逐设备生成单设备 .config 编译
#  - 收集产物（bin / .config / .manifest / .config.buildinfo / ipk|apk），重命名，生成签名，打包日志与 app
#  - 将产物放到 artifacts/ 供 workflow 上传到 Release
#
# 使用方法：在 workflow 中通过 env 传入 REPO_URL, REPO_BRANCH, REPO_SHORT, CHIP, CONFIGS_DIR, ARTIFACT_DIR, LOG_DIR
# 例如： REPO_URL=https://github.com/laipeng668/openwrt.git REPO_BRANCH=master REPO_SHORT=openwrt CHIP=ipq60xx

set -euo pipefail
IFS=$'\n\t'

# ---- 环境变量（可被 workflow 覆盖） ----
REPO_URL="${REPO_URL:-}"
REPO_BRANCH="${REPO_BRANCH:-master}"
REPO_SHORT="${REPO_SHORT:-openwrt}"
CHIP="${CHIP:-ipq60xx}"
CONFIGS_DIR="${CONFIGS_DIR:-configs}"
ARTIFACT_DIR="${ARTIFACT_DIR:-artifacts}"
LOG_DIR="${LOG_DIR:-logs}"
BUILD_ORDER="${BUILD_ORDER:-Ultra Max Pro}"
NPROC="${NPROC:-$(nproc)}"
GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"

# ---- 目录 ----
WORKDIR="$GITHUB_WORKSPACE/build_$REPO_SHORT"
UPSTREAM_DIR="$WORKDIR/upstream"
OUTPUT_DIR="$GITHUB_WORKSPACE/$ARTIFACT_DIR"
TMP_DIR="$WORKDIR/tmp"
LOG_FILE="$GITHUB_WORKSPACE/$LOG_DIR/build_${REPO_SHORT}.log"
ERR_LOG="$GITHUB_WORKSPACE/$LOG_DIR/build_${REPO_SHORT}_error.log"

mkdir -p "$WORKDIR" "$OUTPUT_DIR" "$TMP_DIR" "$GITHUB_WORKSPACE/$LOG_DIR"

# ---- 日志/颜色 ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; PLAIN='\033[0m'
log() { echo -e "${GREEN}[$(date '+%F %T')] $*${PLAIN}" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[$(date '+%F %T')] WARN: $*${PLAIN}" | tee -a "$LOG_FILE"; }
err() { echo -e "${RED}[$(date '+%F %T')] ERROR: $*${PLAIN}" | tee -a "$LOG_FILE"; echo "[$(date '+%F %T')] ERROR: $*" >> "$ERR_LOG"; }

# 错误处理，保存最后 1000 行日志并退出
on_error() {
  local code=$?
  err "发生错误，退出代码 $code"
  echo "---- 错误发生时的最后 1000 行日志 ----" >> "$ERR_LOG"
  tail -n 1000 "$LOG_FILE" >> "$ERR_LOG" || true
  exit "$code"
}
trap 'on_error' ERR

# ---- 基本检查 ----
if [ -z "$REPO_URL" ]; then
  err "环境变量 REPO_URL 未设置"
  exit 2
fi

log "开始构建: repo=${REPO_SHORT} url=${REPO_URL} branch=${REPO_BRANCH} chip=${CHIP}"
log "工作目录: $WORKDIR"

# ---- 克隆上游仓库（浅克隆） ----
cd "$WORKDIR"
if [ -d "$UPSTREAM_DIR" ]; then
  log "发现已有上游仓库，删除重克隆"
  rm -rf "$UPSTREAM_DIR"
fi

log "克隆上游仓库: $REPO_URL @ $REPO_BRANCH"
git clone --depth=1 -b "$REPO_BRANCH" "$REPO_URL" "$UPSTREAM_DIR" >> "$LOG_FILE" 2>&1

# 复制 configs 到临时目录（configs 在本仓库）
if [ ! -d "$GITHUB_WORKSPACE/$CONFIGS_DIR" ]; then
  err "找不到 configs 目录: $GITHUB_WORKSPACE/$CONFIGS_DIR"
  exit 3
fi
cp -a "$GITHUB_WORKSPACE/$CONFIGS_DIR" "$TMP_DIR/"

# ---- 合并 config 的函数 ----
# 合并顺序： chip_base + repo_base + package_config
merge_configs() {
  local chip_base="$TMP_DIR/${CHIP}_base.config"
  local repo_base="$TMP_DIR/${REPO_SHORT}_base.config"
  local package_cfg="$1"   # 完整路径
  local outcfg="$2"

  log "合并配置： $chip_base + $repo_base + $package_cfg -> $outcfg"

  # 如果文件不存在，使用空文件替代
  : > "$outcfg"
  local srcs=()
  [ -f "$chip_base" ] && srcs+=("$chip_base")
  [ -f "$repo_base" ] && srcs+=("$repo_base")
  [ -f "$package_cfg" ] && srcs+=("$package_cfg")

  # 将所有行按顺序读入，用最后出现的 key 覆盖前面的值
  awk '
    function trim(s){gsub(/^[ \t]+|[ \t]+$/,"",s); return s}
    {
      line=$0
      # 识别 CONFIG_* 变量名（注释形式 # CONFIG_xxx is not set 也识别）
      if (match(line, /^[[:space:]]*#?[[:space:]]*(CONFIG_[A-Za-z0-9_]+)(.*)$/, m)) {
        key=m[1]
        last[key]=line
        order[key]=NR
      } else {
        # 非 CONFIG_* 行直接保存为__COMMENT_N
        comment[++c]=line
      }
    }
    END {
      # 先输出非 CONFIG_* 行（原样）
      for (i=1;i<=c;i++) print comment[i]
      # 输出 CONFIG_*，按字母顺序稳定输出
      n=asorti(last, sorted)
      for (i=1;i<=n;i++) print last[sorted[i]]
    }
  ' "${srcs[@]}" > "$outcfg"
}

# ---- 提取设备列表函数 ----
# 从合并后的 config 中提取所有设备名（只包含 =y 的）
extract_devices() {
  local cfg="$1"
  awk '/^CONFIG_TARGET_DEVICE_.*=y/ {
    if (match($0, /_DEVICE_([^=]+)=y/, m)) print m[1]
  }' "$cfg" | sort -u
}

# ---- 设备级别 .config 生成函数 ----
# 参数： $1 merged_config $2 device_name $3 out_config
generate_device_config() {
  local merged="$1"
  local device="$2"
  local out="$3"

  log "生成设备配置: $device -> $out"

  awk -v keep="$device" '
    # 如果匹配到 CONFIG_TARGET_DEVICE_*_DEVICE_<dev>=y
    {
      line=$0
      if (match(line,/^(CONFIG_TARGET_DEVICE_[^_]+_DEVICE_)([^=]+)=(y|n)/,m)) {
        key=m[1]; dev=m[2]; val=m[3]
        if (dev==keep) {
          print key dev "=y"
        } else {
          printf("# CONFIG_TARGET_DEVICE_%s is not set\n", dev)
        }
      } else if (match(line,/^# CONFIG_TARGET_DEVICE_[^_]+_DEVICE_([^ ]+) is not set/,m)) {
        dev=m[1]
        if (dev==keep) {
          printf("CONFIG_TARGET_DEVICE_%s=y\n", dev)
        } else {
          print line
        }
      } else {
        print line
      }
    }
  ' "$merged" > "$out"
}

# ---- 编译单个设备的函数 ----
build_device() {
  local cfg="$1"   # 完整 .config 文件路径（已经只保留一个 device）
  local profile="$2" # Pro/Max/Ultra
  local device="$3"

  log "开始为 device=$device profile=$profile 构建"

  cd "$UPSTREAM_DIR"
  # 复制 config 到上游 repo 的 .config
  cp "$cfg" .config

  # 执行 defconfig，生成默认配置
  log "执行 make defconfig"
  make defconfig >> "$LOG_FILE" 2>&1

  # 并行编译（这里只做 image，省略全部 packages 的 rebuild）
  # 可视需要调整 make target（images 或 full）
  log "开始 make -j$NPROC V=s"
  if ! make -j"$NPROC" V=s >> "$LOG_FILE" 2>&1; then
    err "make 失败，见日志 $LOG_FILE"
    return 1
  fi

  # 编译完成后收集产物（按规则重命名）
  # bin 路径通常在 bin/targets/<target>/<subtarget>/
  local bins_root="$UPSTREAM_DIR/bin/targets"
  if [ ! -d "$bins_root" ]; then
    warn "未找到 bin/targets，构建可能失败或路径不同: $bins_root"
  fi

  # 查找 factory/sysupgrade 固件文件
  local found=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    found=1
    local fname=$(basename "$f")
    # 判断是否 factory 或 sysupgrade
    local suffix=""
    if echo "$fname" | grep -qE 'factory'; then suffix="factory"; else suffix="sysupgrade"; fi
    local ext="${fname##*.}"
    # 确定重命名规则： repo_short-chip-device-(factory|sysupgrade)-profile.bin
    local newname="${REPO_SHORT}-${CHIP}-${device}-${suffix}-${profile}.bin"
    mkdir -p "$OUTPUT_DIR/${REPO_SHORT}/${profile}"
    cp -f "$f" "$OUTPUT_DIR/${REPO_SHORT}/${profile}/$newname"
    log "复制固件: $f -> $OUTPUT_DIR/${REPO_SHORT}/${profile}/$newname"

    # 生成 sha256sum
    sha256sum "$OUTPUT_DIR/${REPO_SHORT}/${profile}/$newname" > "$OUTPUT_DIR/${REPO_SHORT}/${profile}/$newname.sha256"
  done < <(find "$bins_root" -type f -iregex '.*\(factory\|sysupgrade\).*\.bin$' || true)

  if [ "$found" -eq 0 ]; then
    warn "未找到 factory/sysupgrade 固件（可能构建未产生预期文件）"
  fi

  # 复制 .config、.manifest、.config.buildinfo（如存在）
  local base_manifest_dir="$UPSTREAM_DIR"
  for f in $(find "$base_manifest_dir" -maxdepth 3 -type f -name '*.manifest' -o -name '*.config.buildinfo' -o -name '*.config' 2>/dev/null); do
    # 对文件按规则重命名： repo_short-chip-device-profile.ext
    local ext="${f##*.}"
    local dest="$OUTPUT_DIR/${REPO_SHORT}/${profile}/${REPO_SHORT}-${CHIP}-${device}-${profile}.${ext}"
    # 允许覆盖
    cp -f "$f" "$dest" || true
    log "复制元数据: $f -> $dest"
  done

  # 收集 ipk/apk 包到 app 目录（根据 CONFIG_USE_APK 改变后缀）
  local pkg_dir="$UPSTREAM_DIR/bin/packages"
  if [ -d "$pkg_dir" ]; then
    mkdir -p "$OUTPUT_DIR/${REPO_SHORT}/${profile}/app"
    # 匹配 .ipk 或 .apk
    find "$pkg_dir" -type f \( -name '*.ipk' -o -name '*.apk' \) -exec cp -f {} "$OUTPUT_DIR/${REPO_SHORT}/${profile}/app/" \;
  fi

  log "设备 $device profile $profile 构建并收集产物完成"
  return 0
}

# ---- 主流程：按 BUILD_ORDER 合并并编译 ----
for profile in $BUILD_ORDER; do
  PROFILE_CFG="$TMP_DIR/${profile}.config"
  # package config 文件名举例： Ultra.config Max.config Pro.config
  if [ -f "$TMP_DIR/${profile}.config" ]; then
    PACKAGE_CFG="$TMP_DIR/${profile}.config"
  else
    # 兼容大小写或 .config 扩展名
    if [ -f "$TMP_DIR/${profile}.Config" ]; then PACKAGE_CFG="$TMP_DIR/${profile}.Config"; fi
  fi

  # 合并：chip_base + repo_base + PACKAGE_CFG
  MERGED_CFG="$TMP_DIR/merged_${REPO_SHORT}_${profile}.config"
  merge_configs "$PACKAGE_CFG" "$MERGED_CFG"

  # 提取设备列表
  devices=$(extract_devices "$MERGED_CFG" || true)
  if [ -z "$devices" ]; then
    warn "在合并后的配置中未找到任何设备（profile=$profile），跳过"
    continue
  fi

  # 对每个 device 生成 per-device config 并构建
  for device in $devices; do
    PER_DEV_CFG="$TMP_DIR/${REPO_SHORT}_${profile}_${device}.config"
    generate_device_config "$MERGED_CFG" "$device" "$PER_DEV_CFG"

    # 构建 device（会在上游 repo 下运行 make）
    if ! build_device "$PER_DEV_CFG" "$profile" "$device"; then
      err "device=$device profile=$profile 构建失败，终止后续任务"
      exit 1
    fi
  done
done

# ---- 打包 artifacts（产物/日志/app） ----
cd "$GITHUB_WORKSPACE"
tar -czf "$OUTPUT_DIR/${CHIP}-config.tar.gz" -C "$OUTPUT_DIR" . || true
tar -czf "$OUTPUT_DIR/${CHIP}-log.tar.gz" -C "$LOG_DIR" . || true
tar -czf "$OUTPUT_DIR/${CHIP}-app.tar.gz" -C "$OUTPUT_DIR" . || true

log "全部构建完成，产物位于 $OUTPUT_DIR"
log "日志位置: $LOG_FILE, 错误日志: $ERR_LOG"
