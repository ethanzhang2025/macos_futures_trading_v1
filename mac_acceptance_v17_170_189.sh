#!/usr/bin/env bash
# v17.170-189 增量验收（19 commit · chart 内 5 个快捷键 overlay/sheet）
#
# 用法（Mac 端）：
#   cd /Users/admin/Documents/MAC版本_期货交易终端/macos_futures_trading_v1
#   git pull
#   chmod +x mac_acceptance_v17_170_189.sh
#   ./mac_acceptance_v17_170_189.sh
#
# 输出：~/Desktop/mac_acceptance_v17_170_189/shots/24-28 · scp 上传到 beelink@vvsvr

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$HOME/Desktop/mac_acceptance_v17_170_189"
SHOTS_DIR="$OUT_DIR/shots"
REMOTE_DIR="/tmp/mac_acceptance_v17_170_189"
BUILD_PATH="/tmp/build_v1730_b1"

APP_PID=""

cleanup() {
    local rc=$?
    if [[ -n "$APP_PID" ]]; then
        kill "$APP_PID" 2>/dev/null || true
    fi
    osascript -e 'tell application "MainApp" to quit' 2>/dev/null || true
    osascript -e 'tell application "FuturesTerminal" to quit' 2>/dev/null || true

    local n=$(ls "$SHOTS_DIR" 2>/dev/null | wc -l | tr -d ' ')
    {
        echo "# v17.170-189 增量验收结果 · $(date '+%Y-%m-%d %H:%M:%S')"
        echo "退出码: $rc"
        echo "截图数: $n / 5"
        echo "macOS: $(sw_vers -productVersion 2>/dev/null)"
        ls "$SHOTS_DIR" 2>/dev/null | sort | sed 's/^/  /'
    } > "$OUT_DIR/summary.txt"

    if ssh -o ConnectTimeout=5 beelink@vvsvr "echo ok" > /dev/null 2>&1; then
        ssh beelink@vvsvr "rm -rf ${REMOTE_DIR} && mkdir -p ${REMOTE_DIR}"
        scp -q "$OUT_DIR/summary.txt" beelink@vvsvr:"${REMOTE_DIR}/" 2>/dev/null
        [[ -d "$SHOTS_DIR" ]] && scp -rq "$SHOTS_DIR" beelink@vvsvr:"${REMOTE_DIR}/" 2>/dev/null
        echo "✅ scp 完成 · 告诉 Linux 端：'v17.170-189 增量验收完成 · 截图 N=$n'"
    else
        echo "⚠️ SSH 不通 · 手动 scp：scp -r $OUT_DIR beelink@vvsvr:${REMOTE_DIR}/"
    fi
}
trap cleanup EXIT

mkdir -p "$SHOTS_DIR"
rm -f "$SHOTS_DIR"/24_*.png "$SHOTS_DIR"/25_*.png "$SHOTS_DIR"/26_*.png "$SHOTS_DIR"/27_*.png "$SHOTS_DIR"/28_*.png 2>/dev/null

echo "════════════════════════════════════════════════════"
echo " v17.170-189 增量验收 · 5 项主图内交互"
echo "════════════════════════════════════════════════════"
echo " 输出 → $OUT_DIR"
date

# Phase 1: 启动 app（假定 build 已经 mac_acceptance.sh --skip-shots 跑过）
echo ""
echo "▶ 启动 swift run MainApp ..."
nohup swift run MainApp --build-path "$BUILD_PATH" > "$OUT_DIR/app_stdout.log" 2>&1 &
APP_PID=$!
echo "app pid = $APP_PID · 等待 12s 让 app 完全启动 + Sina 首次拉取就位"
sleep 12

# Phase 2: 调用 applescript（开 ⌘N + 5 项快捷键 + 截图）
echo ""
echo "▶ 调用 mac_acceptance_v17_170_189.applescript（自动 ~15s）"
if [[ ! -f "$SCRIPT_DIR/mac_acceptance_v17_170_189.applescript" ]]; then
    echo "⚠️ 未找到 applescript · 退出"
    exit 1
fi
osascript "$SCRIPT_DIR/mac_acceptance_v17_170_189.applescript" "$SHOTS_DIR" 2>&1 | tee "$OUT_DIR/capture.log"

# 关 app（cleanup 兜底再做一次）
echo ""
echo "关闭 app ..."
osascript -e 'tell application "MainApp" to quit' 2>/dev/null || true
sleep 1
kill "$APP_PID" 2>/dev/null || true
APP_PID=""

SHOT_COUNT=$(ls "$SHOTS_DIR" 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "════════════════════════════════════════════════════"
echo " ✅ 完成 · 截图 $SHOT_COUNT / 5"
echo "════════════════════════════════════════════════════"
date
