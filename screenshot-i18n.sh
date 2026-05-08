#!/bin/bash
# Mac 端 i18n 验收自动截图 + 上传脚本
#
# 用法：
#   ./screenshot-i18n.sh <lang> [windows]
#     lang     : zh-Hans | en
#     windows  : (默认 all 全 9 张)
#                单张:   06
#                多张:   06,07
#                范围:   04-06
#                全部:   all
#
# 例：
#   ./screenshot-i18n.sh en              # 全 9 张（清旧 + 全传）
#   ./screenshot-i18n.sh en 06           # 只截/上传 Workspace 一张（保留远端其他）
#   ./screenshot-i18n.sh en 04-06        # 截 4-6 三张
#   ./screenshot-i18n.sh en 06,09        # 截 6+9 两张

set -e

LANG_TAG="${1:-}"
WINDOWS_ARG="${2:-all}"

if [[ "$LANG_TAG" != "zh-Hans" && "$LANG_TAG" != "en" ]]; then
  echo "用法: $0 <zh-Hans|en> [windows]"
  echo "  windows: all (默认) / 06 / 06,07 / 04-06"
  exit 1
fi

SHOT_DIR="$HOME/i18n_screens/$LANG_TAG"
mkdir -p "$SHOT_DIR"

ALL_WINDOWS=(
  "01_KLine主窗"
  "02_自选合约_⌘L"
  "03_预警_文件→Alerts"
  "04_交易日志_文件→TradeJournal"
  "05_复盘工作台_文件→ReplayWorkspace"
  "06_工作区模板_文件→WorkspaceTemplates"
  "07_公式编辑器_⌘⌥F"
  "08_多图表_⌘⌥M"
  "09_模拟训练_⌘⇧T"
)

# 解析 windows 参数 → 索引列表（0-based）
INDICES=()
if [[ "$WINDOWS_ARG" == "all" ]]; then
  INDICES=(0 1 2 3 4 5 6 7 8)
elif [[ "$WINDOWS_ARG" == *","* ]]; then
  IFS=',' read -ra ITEMS <<< "$WINDOWS_ARG"
  for item in "${ITEMS[@]}"; do
    INDICES+=( $((10#$item - 1)) )
  done
elif [[ "$WINDOWS_ARG" == *"-"* ]]; then
  START="${WINDOWS_ARG%%-*}"
  END="${WINDOWS_ARG##*-}"
  for ((i=10#$START; i<=10#$END; i++)); do
    INDICES+=( $((i - 1)) )
  done
else
  INDICES+=( $((10#$WINDOWS_ARG - 1)) )
fi

# 全部模式才清旧图（部分模式保留旧的 · 只覆盖目标窗口）
if [[ "$WINDOWS_ARG" == "all" ]]; then
  rm -f "$SHOT_DIR"/*.png
fi

echo "════════════════════════════════════════"
echo " i18n 验收截图 · 语言: $LANG_TAG · ${#INDICES[@]} 个窗口"
echo "════════════════════════════════════════"
echo ""
echo "前提：✓ 系统语言已切到 [$LANG_TAG] · App 已重启"
echo ""
read -p "✅ 就绪？回车开始（Ctrl+C 取消）: " _

for idx in "${INDICES[@]}"; do
  window="${ALL_WINDOWS[$idx]}"
  OUT="$SHOT_DIR/${LANG_TAG}_${window}.png"
  echo ""
  echo "▶ [$window]"
  echo "  1. 在 App 内打开/激活该窗口"
  echo "  2. 回车 → 鼠标变相机 → 点击要截的窗口"
  read -p "  ⏎ " _
  screencapture -W -o "$OUT" || true
  if [[ -f "$OUT" ]]; then
    echo "  ✅ $(basename "$OUT") · $(du -h "$OUT" | cut -f1)"
  else
    echo "  ⚠️  未保存 · 重试一次（回车继续）"
    read -p "  ⏎ " _
    screencapture -W -o "$OUT" || true
    [[ -f "$OUT" ]] && echo "  ✅ 重试成功" || echo "  ❌ 跳过"
  fi
done

echo ""
echo "════════════════════════════════════════"
echo " 截图完成 · 准备上传"
echo "════════════════════════════════════════"
echo ""
echo "▶ 上传 → beelink@vvsvr:~/debug_img/i18n_验收/$LANG_TAG/"

REMOTE_DIR="/home/beelink/debug_img/i18n_验收/$LANG_TAG"

# 全部模式：清远端旧 + 全传
# 部分模式：仅传本次截的（保留远端其他）
if [[ "$WINDOWS_ARG" == "all" ]]; then
  ssh beelink@vvsvr "rm -f '$REMOTE_DIR'/*.png && mkdir -p '$REMOTE_DIR'"
  scp "$SHOT_DIR"/*.png "beelink@vvsvr:$REMOTE_DIR/"
else
  ssh beelink@vvsvr "mkdir -p '$REMOTE_DIR'"
  for idx in "${INDICES[@]}"; do
    window="${ALL_WINDOWS[$idx]}"
    OUT="$SHOT_DIR/${LANG_TAG}_${window}.png"
    [[ -f "$OUT" ]] && scp "$OUT" "beelink@vvsvr:$REMOTE_DIR/"
  done
fi

echo ""
echo "✅ 上传完成 · 远程: beelink@vvsvr:$REMOTE_DIR/"
