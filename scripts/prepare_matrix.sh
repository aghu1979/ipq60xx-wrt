#!/usr/bin/env bash
# prepare_matrix.sh
#  - 从 configs 中按 repo_base + chip_base + profile 合并配置
#  - 提取 device 列表（CONFIG_TARGET_DEVICE_...=y）
#  - 以 JSON 数组输出每个条目 { "repo_url": "...", "repo_branch": "...", "repo_short": "...", "profile": "...", "device": "..." }
#  - Ultra 将会优先输出（即列表中 Ultra 在前）
set -euo pipefail
IFS=$'\n\t'

WORKDIR=$(pwd)
CONFIGS_DIR="$WORKDIR/configs"
CHIP="ipq60xx"

# 仓库列表（与 workflow 中保持一致）
repos=(
  "https://github.com/laipeng668/immortalwrt.git|master|immwrt"
  "https://github.com/laipeng668/openwrt.git|master|openwrt"
  "https://github.com/laipeng668/openwrt-6.x.git|k6.12-nss|libwrt"
)

profiles=(Ultra Max Pro)

# 准备合并函数（简单 awk 合并，后出现的 key 覆盖前面）
merge_files() {
  local out="$1"
  shift
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
  ' "$@" > "$out"
}

json_items=()

for r in "${repos[@]}"; do
  IFS='|' read -r repo_url repo_branch repo_short <<< "$r"
  chip_base="$CONFIGS_DIR/${CHIP}_base.config"
  repo_base="$CONFIGS_DIR/${repo_short}_base.config"
  # profiles: Ultra first
  for profile in "${profiles[@]}"; do
    profile_cfg="$CONFIGS_DIR/${profile}.config"
    merged_tmp=$(mktemp)
    # Build the list of sources to merge
    srcs=()
    [ -f "$chip_base" ] && srcs+=("$chip_base")
    [ -f "$repo_base" ] && srcs+=("$repo_base")
    [ -f "$profile_cfg" ] && srcs+=("$profile_cfg")
    if [ ${#srcs[@]} -eq 0 ]; then
      # no config sources, skip
      continue
    fi
    merge_files "$merged_tmp" "${srcs[@]}"
    # extract devices
    devices=$(awk '/^CONFIG_TARGET_DEVICE_.*=y/ {
      if (match($0, /_DEVICE_([^=]+)=y/, m)) print m[1]
    }' "$merged_tmp" | sort -u)
    if [ -z "$devices" ]; then
      # no devices found for this profile; continue
      rm -f "$merged_tmp"
      continue
    fi
    for device in $devices; do
      # append JSON object (escape double quotes etc.)
      repo_url_esc=$(printf '%s' "$repo_url" | sed 's/"/\\"/g')
      repo_branch_esc=$(printf '%s' "$repo_branch" | sed 's/"/\\"/g')
      repo_short_esc=$(printf '%s' "$repo_short" | sed 's/"/\\"/g')
      profile_esc=$(printf '%s' "$profile" | sed 's/"/\\"/g')
      device_esc=$(printf '%s' "$device" | sed 's/"/\\"/g')
      json_items+=("{\"repo_url\":\"${repo_url_esc}\",\"repo_branch\":\"${repo_branch_esc}\",\"repo_short\":\"${repo_short_esc}\",\"profile\":\"${profile_esc}\",\"device\":\"${device_esc}\"}")
    done
    rm -f "$merged_tmp"
  done
done

# output JSON array
printf '[%s]\n' "$(IFS=,; echo "${json_items[*]}")"
