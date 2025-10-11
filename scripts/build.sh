#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# build.sh - 支持单 device/profile 模式（用于 matrix）或批量模式
set -euo pipefail
IFS=$'\n\t'

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

PROFILE_ENV="${PROFILE:-}"
DEVICE_ENV="${DEVICE:-}"

WORKDIR="$GITHUB_WORKSPACE/build_${REPO_SHORT}"
UPSTREAM_DIR="$WORKDIR/upstream"
OUTPUT_DIR="$GITHUB_WORKSPACE/$ARTIFACT_DIR"
TMP_DIR="$WORKDIR/tmp"
LOG_FILE="$GITHUB_WORKSPACE/$LOG_DIR/build_${REPO_SHORT}.log"
ERR_LOG="$GITHUB_WORKSPACE/$LOG_DIR/build_${REPO_SHORT}_error.log"

mkdir -p "$WORKDIR" "$OUTPUT_DIR" "$TMP_DIR" "$GITHUB_WORKSPACE/$LOG_DIR"

log() { echo "[$(date '+%F %T')] [INFO] $*" | tee -a "$LOG_FILE"; }
warn() { echo "[$(date '+%F %T')] [WARN] $*" | tee -a "$LOG_FILE"; }
err() { echo "[$(date '+%F %T')] [ERROR] $*" | tee -a "$LOG_FILE"; echo "[$(date '+%F %T')] ERROR: $*" >> "$ERR_LOG"; }

on_error() {
  local code=$?
  err "发生错误，退出代码 $code"
  echo "---- 错误发生时的最后 1000 行日志 ----" >> "$ERR_LOG"
  tail -n 1000 "$LOG_FILE" >> "$ERR_LOG" || true
  exit "$code"
}
trap 'on_error' ERR

if [ -z "$REPO_URL" ]; then
  err "环境变量 REPO_URL 未设置"
  exit 2
fi

log "开始构建: repo=${REPO_SHORT} url=${REPO_URL} branch=${REPO_BRANCH} chip=${CHIP}"
log "工作目录: $WORKDIR"

cd "$WORKDIR"
rm -rf "$UPSTREAM_DIR"
log "克隆上游仓库: $REPO_URL @ $REPO_BRANCH"
git clone --depth=1 -b "$REPO_BRANCH" "$REPO_URL" "$UPSTREAM_DIR" >> "$LOG_FILE" 2>&1

# 在上游仓库中运行用户 scripts/script.sh（if present）
if [ -f "$GITHUB_WORKSPACE/scripts/script.sh" ]; then
  log "在上游仓库执行 scripts/script.sh"
  pushd "$UPSTREAM_DIR" > /dev/null
  export LOG_DIR="$GITHUB_WORKSPACE/$LOG_DIR"
  export LOG_FILE="$LOG_DIR/script.log"
  export ERR_LOG="$LOG_DIR/script_error.log"
  mkdir -p "$LOG_DIR"
  if ! bash "$GITHUB_WORKSPACE/scripts/script.sh" >> "$LOG_FILE" 2>&1; then
    err "scripts/script.sh 执行失败，详见 $LOG_FILE"
    popd > /dev/null
    exit 1
  fi
  popd > /dev/null
  log "scripts/script.sh 执行完成"
else
  warn "未找到仓库根的 scripts/script.sh，跳过"
fi

# 复制 configs
if [ ! -d "$GITHUB_WORKSPACE/$CONFIGS_DIR" ]; then
  err "找不到 configs 目录: $GITHUB_WORKSPACE/$CONFIGS_DIR"
  exit 3
fi
cp -a "$GITHUB_WORKSPACE/$CONFIGS_DIR" "$TMP_DIR/"

# 合并函数：chip_base + repo_base + package_cfg（存在则加）
merge_configs() {
  local package_cfg="$1"; local outcfg="$2"
  local chip_base="$TMP_DIR/${CHIP}_base.config"
  local repo_base="$TMP_DIR/${REPO_SHORT}_base.config"

  log "合并配置： $chip_base + $repo_base + $package_cfg -> $outcfg"
  : > "$outcfg"
  local srcs=()
  [ -f "$chip_base" ] && srcs+=("$chip_base")
  [ -f "$repo_base" ] && srcs+=("$repo_base")
  [ -n "$package_cfg" ] && [ -f "$package_cfg" ] && srcs+=("$package_cfg")

  if [ ${#srcs[@]} -eq 0 ]; then
    log "没有配置来源，生成空配置 $outcfg"
    : > "$outcfg"
    return 0
  fi

  awk '
    {
      line=$0
      if (match(line, /^[[:space:]]*#?[[:space:]]*(CONFIG_[A-Za-z0-9_]+)(.*)$/, m)) {
        key=m[1]
        last[key]=line
      } else {
        comment[++c]=line
      }
    }
    END {
      for (i=1;i<=c;i++) print comment[i]
      n=asorti(last, sorted)
      for (i=1;i<=n;i++) print last[sorted[i]]
    }
  ' "${srcs[@]}" > "$outcfg"
}

extract_devices() {
  local cfg="$1"
  awk '/^CONFIG_TARGET_DEVICE_.*=y/ {
    if (match($0, /_DEVICE_([^=]+)=y/, m)) print m[1]
  }' "$cfg" | sort -u
}

generate_device_config() {
  local merged="$1"; local device="$2"; local out="$3"
  log "生成设备配置: $device -> $out"
  awk -v keep="$device" '
    {
      line=$0
      if (match(line,/^(CONFIG_TARGET_DEVICE_[^_]+_DEVICE_)([^=]+)=(y|n)/,m)) {
        key=m[1]; dev=m[2]
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

# 提取 luci-app 列表（从 per-device .config 中查找 CONFIG_PACKAGE_luci-*)
extract_luci_apps() {
  local cfg="$1"
  awk -F'=' '/^CONFIG_PACKAGE_luci-/ {
    gsub(/CONFIG_PACKAGE_/, "", $1)
    pkg=$1
    gsub(/[ \t"]/, "", pkg)
    print pkg
  }' "$cfg" | sort -u
}

# 尝试从 manifest 或 config.buildinfo 中提取内核版本（若找不到则空）
extract_kernel_version() {
  local basedir="$1"
  # try manifest
  local mf=$(find "$basedir" -maxdepth 2 -type f -name '*.manifest' | head -n1 || true)
  if [ -n "$mf" ]; then
    # 试着解析常见的关键字
    grep -E 'Linux|kernel|KERNEL|Kernel' "$mf" -m1 -n >/dev/null 2>&1 || true
    kv=$(grep -E 'Linux|kernel|KERNEL|Kernel' "$mf" | head -n1 || true)
    if [ -n "$kv" ]; then
      echo "$kv" | tr -d '\r\n'
      return 0
    fi
  fi
  # try config.buildinfo
  local bi=$(find "$basedir" -maxdepth 2 -type f -name '*.config.buildinfo' | head -n1 || true)
  if [ -n "$bi" ]; then
    kv=$(grep -E 'KERNEL|kernel|Linux' "$bi" | head -n1 || true)
    if [ -n "$kv" ]; then
      echo "$kv" | tr -d '\r\n'
      return 0
    fi
  fi
  echo ""
}

# 构建并收集产物
build_device() {
  local cfg="$1"; local profile="$2"; local device="$3"
  log "开始构建 device=${device} profile=${profile}"
  cd "$UPSTREAM_DIR"
  cp "$cfg" .config
  log "make defconfig"
  make defconfig >> "$LOG_FILE" 2>&1
  log "开始 make -j$NPROC V=s"
  if ! make -j"$NPROC" V=s >> "$LOG_FILE" 2>&1; then
    err "make 失败"
    return 1
  fi

  # 收集固件
  local bins_root="$UPSTREAM_DIR/bin/targets"
  local found=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    found=1
    local fname=$(basename "$f")
    local suffix=""
    if echo "$fname" | grep -qi 'factory'; then suffix="factory"; else suffix="sysupgrade"; fi
    local newname="${REPO_SHORT}-${CHIP}-${device}-${suffix}-${profile}.bin"
    mkdir -p "$OUTPUT_DIR/${REPO_SHORT}/${profile}/${device}"
    cp -f "$f" "$OUTPUT_DIR/${REPO_SHORT}/${profile}/${device}/$newname"
    sha256sum "$OUTPUT_DIR/${REPO_SHORT}/${profile}/${device}/$newname" > "$OUTPUT_DIR/${REPO_SHORT}/${profile}/${device}/$newname.sha256"
    log "复制固件: $f -> $OUTPUT_DIR/${REPO_SHORT}/${profile}/${device}/$newname"
  done < <(find "$bins_root" -type f -iregex '.*\(factory\|sysupgrade\).*\.bin$' || true)

  if [ "$found" -eq 0 ]; then
    warn "未找到 factory/sysupgrade 固件"
  fi

  # 复制元数据
  for f in $(find "$UPSTREAM_DIR" -maxdepth 3 -type f \( -name '*.manifest' -o -name '*.config.buildinfo' -o -name '*.config' \) 2>/dev/null); do
    local ext="${f##*.}"
    local dest="$OUTPUT_DIR/${REPO_SHORT}/${profile}/${device}/${REPO_SHORT}-${CHIP}-${device}-${profile}.${ext}"
    cp -f "$f" "$dest" || true
    log "复制元数据: $f -> $dest"
  done

  # 收集 ipk/apk
  local pkg_dir="$UPSTREAM_DIR/bin/packages"
  if [ -d "$pkg_dir" ]; then
    mkdir -p "$OUTPUT_DIR/${REPO_SHORT}/${profile}/${device}/app"
    find "$pkg_dir" -type f \( -name '*.ipk' -o -name '*.apk' \) -exec cp -f {} "$OUTPUT_DIR/${REPO_SHORT}/${profile}/${device}/app/" \;
  fi

  # 生成 metadata.json
  meta_dir="$OUTPUT_DIR/${REPO_SHORT}/${profile}/${device}"
  mkdir -p "$meta_dir"
  kernel=$(extract_kernel_version "$UPSTREAM_DIR")
  luci_list=$(extract_luci_apps "$cfg" | jq -R -s -c 'split("\n")[:-1]' 2>/dev/null || python3 - <<PY
import sys, json
s=sys.stdin.read().strip().splitlines()
s=[x for x in s if x.strip()!='']
print(json.dumps(s))
PY <<EOF
$(extract_luci_apps "$cfg" | sed 's/"/\\"/g')
EOF
)
  # Fallback if previous failed: use simple comma separated list
  if [ -z "$luci_list" ] || [ "$luci_list" = "null" ]; then
    luci_list="[]"
  fi

  # list artifacts
  arts=$(find "$meta_dir" -type f -maxdepth 2 -printf "%P\n" 2>/dev/null | jq -R -s -c 'split("\n")[:-1]' 2>/dev/null || true)
  if [ -z "$arts" ]; then
    # fallback: minimal
    arts="[]"
  fi

  cat > "$meta_dir/metadata.json" <<EOF
{
  "repo_short": "${REPO_SHORT}",
  "profile": "${profile}",
  "device": "${device}",
  "kernel_version": $(python3 - <<PY
import json,sys
k=${kernel!+repr(kernel) if kernel else "''"}
print(json.dumps($kernel) if False else json.dumps("$kernel"))
PY
) ,
  "luci_apps": ${luci_list},
  "artifacts": ${arts}
}
EOF

  log "生成 metadata.json 在 $meta_dir/metadata.json"
  return 0
}

# 主流程：两种模式
if [ -n "$PROFILE_ENV" ] && [ -n "$DEVICE_ENV" ]; then
  profile="$PROFILE_ENV"; device="$DEVICE_ENV"
  PACKAGE_CFG=""
  if [ -f "$TMP_DIR/${profile}.config" ]; then PACKAGE_CFG="$TMP_DIR/${profile}.config"; fi
  if [ -f "$TMP_DIR/${profile}.Config" ]; then PACKAGE_CFG="$TMP_DIR/${profile}.Config"; fi
  MERGED_CFG="$TMP_DIR/merged_${REPO_SHORT}_${profile}.config"
  merge_configs "$PACKAGE_CFG" "$MERGED_CFG"
  PER_DEV_CFG="$TMP_DIR/${REPO_SHORT}_${profile}_${device}.config"
  generate_device_config "$MERGED_CFG" "$device" "$PER_DEV_CFG"
  if ! build_device "$PER_DEV_CFG" "$profile" "$device"; then
    err "单设备构建失败"
    exit 1
  fi
else
  for profile in $BUILD_ORDER; do
    PACKAGE_CFG=""
    if [ -f "$TMP_DIR/${profile}.config" ]; then PACKAGE_CFG="$TMP_DIR/${profile}.config"; fi
    if [ -f "$TMP_DIR/${profile}.Config" ]; then PACKAGE_CFG="$TMP_DIR/${profile}.Config"; fi
    MERGED_CFG="$TMP_DIR/merged_${REPO_SHORT}_${profile}.config"
    merge_configs "$PACKAGE_CFG" "$MERGED_CFG"
    devices=$(extract_devices "$MERGED_CFG" || true)
    if [ -z "$devices" ]; then
      warn "profile=$profile 未找到 device，跳过"
      continue
    fi
    for device in $devices; do
      PER_DEV_CFG="$TMP_DIR/${REPO_SHORT}_${profile}_${device}.config"
      generate_device_config "$MERGED_CFG" "$device" "$PER_DEV_CFG"
      if ! build_device "$PER_DEV_CFG" "$profile" "$device"; then
        err "device=$device profile=$profile 构建失败"
        exit 1
      fi
    done
  done
fi

# 打包 artifacts/logs
cd "$GITHUB_WORKSPACE" || true
tar -czf "$OUTPUT_DIR/${CHIP}-config.tar.gz" -C "$OUTPUT_DIR" . || true
tar -czf "$OUTPUT_DIR/${CHIP}-log.tar.gz" -C "$LOG_DIR" . || true
tar -czf "$OUTPUT_DIR/${CHIP}-app.tar.gz" -C "$OUTPUT_DIR" . || true

log "构建脚本结束，产物位于 $OUTPUT_DIR"
log "日志位于 $LOG_FILE 错误日志： $ERR_LOG"
