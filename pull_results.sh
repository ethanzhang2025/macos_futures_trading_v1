#!/bin/bash
# pull_results.sh · Linux 端 · 拉取 vvsvr 上最新 mac_loop 结果
#
# Claude 用法: ./pull_results.sh
# 输出: /tmp/appium_loop/ 含 result.json / shots/ / ui_tree_*.xml / logs

set -euo pipefail

VVSVR_REMOTE="beelink@vvsvr"
VVSVR_PATH="/home/beelink/debug_img/appium_loop_latest"
LOCAL_DIR="/tmp/appium_loop"

sep() { echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

sep
echo "  pull_results · 拉 vvsvr 最新 mac_loop 结果"
sep
echo ""

rm -rf "$LOCAL_DIR"
mkdir -p "$LOCAL_DIR"

echo "📥 scp -rq $VVSVR_REMOTE:$VVSVR_PATH/* $LOCAL_DIR/"
if ! scp -rq "$VVSVR_REMOTE:$VVSVR_PATH/*" "$LOCAL_DIR/" 2>/dev/null; then
    echo "❌ scp 失败 · 检查:"
    echo "   1. ssh $VVSVR_REMOTE 通否"
    echo "   2. $VVSVR_PATH 在 vvsvr 上存在否（Mac 是否跑过 mac_loop.sh）"
    exit 1
fi
echo ""

# Summary
if [[ -f "$LOCAL_DIR/summary.txt" ]]; then
    echo "📌 Summary:"
    cat "$LOCAL_DIR/summary.txt"
    echo ""
fi

# pytest 结果
if [[ -f "$LOCAL_DIR/result.json" ]]; then
    echo "🧪 pytest 结果:"
    if command -v jq >/dev/null 2>&1; then
        jq '.summary // {}' "$LOCAL_DIR/result.json" 2>/dev/null
        echo ""
        echo "💥 非 pass 用例:"
        jq -r '.tests[]? | select(.outcome != "passed") |
               "  [\(.outcome | ascii_upcase)] \(.nodeid)\n       \(.call.longrepr // .setup.longrepr // "(no trace)" | gsub("\n";" ¶ ") | .[0:200])"' \
               "$LOCAL_DIR/result.json" 2>/dev/null || echo "  (jq 解析失败 · 看原始文件)"
    else
        echo "  (未装 jq · 直接看 $LOCAL_DIR/result.json)"
    fi
    echo ""
fi

# 截图列表
if [[ -d "$LOCAL_DIR/shots" ]] && [[ -n "$(ls -A "$LOCAL_DIR/shots" 2>/dev/null)" ]]; then
    echo "🖼  Screenshots:"
    for f in "$LOCAL_DIR/shots"/*.png "$LOCAL_DIR/shots"/*.jpg; do
        [[ -f "$f" ]] || continue
        bytes=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo "?")
        echo "  $(basename "$f")  (${bytes} bytes)"
    done
    echo ""
fi

# UI tree dumps
if ls "$LOCAL_DIR"/ui_tree_*.xml >/dev/null 2>&1; then
    echo "🌳 UI tree dumps:"
    for f in "$LOCAL_DIR"/ui_tree_*.xml; do
        lines=$(wc -l < "$f" 2>/dev/null || echo "?")
        echo "  $(basename "$f")  ($lines lines)"
    done
    echo ""
fi

sep
echo "  ✅ 结果在 $LOCAL_DIR/"
echo "  Claude 下一步:"
echo "    - Read $LOCAL_DIR/result.json"
echo "    - Read $LOCAL_DIR/shots/*.png 看 UI 状态"
echo "    - Read $LOCAL_DIR/ui_tree_*.xml 找 accessibility id"
sep
