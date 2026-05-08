#!/bin/bash
# Mac 端 i18n 验收自动截图 + 上传脚本
#
# 用法：
#   ./screenshot-i18n.sh zh-Hans   # 验中文系统
#   ./screenshot-i18n.sh en        # 验英文系统
#
# 流程：
#   1. 提示 9 个验收窗口 · 每个用 screencapture -W 让你鼠标点截图
#   2. 完成后自动 scp 到 beelink@vvsvr:~/debug_img/i18n_验收/<lang>/

set -e

LANG_TAG="${1:-}"
if [[ "$LANG_TAG" != "zh-Hans" && "$LANG_TAG" != "en" ]]; then
  echo "用法: $0 <zh-Hans|en>"
  exit 1
fi

SHOT_DIR="$HOME/i18n_screens/$LANG_TAG"
mkdir -p "$SHOT_DIR"
rm -f "$SHOT_DIR"/*.png

WINDOWS=(
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

echo "════════════════════════════════════════"
echo " i18n 验收截图 · 语言: $LANG_TAG"
echo " 共 ${#WINDOWS[@]} 个窗口 · 每个 1 张主界面"
echo "════════════════════════════════════════"
echo ""
echo "前提："
echo "  ✓ 系统语言已切到 [$LANG_TAG] · App 已重启"
echo "  ✓ App 已启动（./run-mac.sh）"
echo ""
read -p "✅ 就绪？回车开始（Ctrl+C 取消）: " _

for window in "${WINDOWS[@]}"; do
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

COUNT=$(ls -1 "$SHOT_DIR"/*.png 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "════════════════════════════════════════"
echo " 截图完成 · 共 $COUNT 张"
echo " 本地: $SHOT_DIR"
echo "════════════════════════════════════════"

if [[ "$COUNT" -eq 0 ]]; then
  echo "❌ 没有截图 · 不上传"
  exit 1
fi

echo ""
echo "▶ 上传 → beelink@vvsvr:~/debug_img/i18n_验收/$LANG_TAG/"

REMOTE_DIR="/home/beelink/debug_img/i18n_验收/$LANG_TAG"
ssh beelink@vvsvr "rm -f '$REMOTE_DIR'/*.png && mkdir -p '$REMOTE_DIR'"
scp "$SHOT_DIR"/*.png "beelink@vvsvr:$REMOTE_DIR/"

echo ""
echo "✅ 上传完成 · 下一步：在 Linux 端让 Claude 分析"
echo "   远程路径: beelink@vvsvr:$REMOTE_DIR/"
