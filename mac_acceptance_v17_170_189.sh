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
APP_NAME=""   # 实际探测到的进程名（MainApp 或 FuturesTerminal）
MAX_LAUNCH_WAIT=180   # 进程出现等待上限（秒）· 给 swift run 首次编译留空间
MAX_WINDOW_WAIT=30    # 窗口出现等待上限（秒）

# 探测当前正在跑的 app 进程名（pgrep -fl 拿到 swift run 子进程实际 name）
detect_app_name() {
    for n in MainApp FuturesTerminal; do
        if pgrep -x "$n" > /dev/null 2>&1; then
            echo "$n"
            return 0
        fi
    done
    return 1
}

# 等 app 主进程出现（pgrep）
wait_for_app_process() {
    local waited=0
    while (( waited < MAX_LAUNCH_WAIT )); do
        if APP_NAME=$(detect_app_name); then
            echo "  ✓ 进程 $APP_NAME 已出现（耗时 ${waited}s）"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
        if (( waited % 10 == 0 )); then
            echo "  ⏳ 仍在等待主程序进程出现... ${waited}/${MAX_LAUNCH_WAIT}s"
        fi
    done
    return 1
}

# 等 app 主窗口可见（通过 System Events 查 windows count > 0）
wait_for_app_window() {
    local waited=0
    while (( waited < MAX_WINDOW_WAIT )); do
        local n
        n=$(osascript -e "tell application \"System Events\" to tell (first process whose name is \"$APP_NAME\") to count of windows" 2>/dev/null || echo 0)
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n > 0 )); then
            echo "  ✓ 主窗口已出现（windows=$n · 耗时 ${waited}s）"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

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

# Phase 1: 启动 app + 等到主进程 + 主窗口都就绪才放行（修 bug：旧版死等 12s）
echo ""
echo "▶ 启动 swift run MainApp ..."
nohup swift run MainApp --build-path "$BUILD_PATH" > "$OUT_DIR/app_stdout.log" 2>&1 &
APP_PID=$!
echo "swift run pid = $APP_PID · 轮询等主程序进程出现（上限 ${MAX_LAUNCH_WAIT}s）"

if ! wait_for_app_process; then
    echo "❌ 主程序进程在 ${MAX_LAUNCH_WAIT}s 内未出现 · 检查 $OUT_DIR/app_stdout.log"
    echo "❌ 不进行截图 · 退出"
    tail -30 "$OUT_DIR/app_stdout.log" 2>/dev/null || true
    exit 2
fi

echo "  ⏳ 等待主窗口出现（上限 ${MAX_WINDOW_WAIT}s）"
if ! wait_for_app_window; then
    echo "❌ 主窗口在 ${MAX_WINDOW_WAIT}s 内未出现 · 不进行截图 · 退出"
    exit 3
fi

# 多缓 3s 让 Sina 首拉 + 主图渲染完成
echo "  ⏳ 额外 3s 让首拉数据 / 主图渲染就位"
sleep 3

# 二次确认进程仍在跑（防止启动后立刻 crash）
if ! pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    echo "❌ 主程序在窗口出现后又消失了（可能 crash）· 不进行截图"
    tail -30 "$OUT_DIR/app_stdout.log" 2>/dev/null || true
    exit 4
fi

# Phase 2: 调用 applescript（开 ⌘N + 5 项快捷键 + 截图）
echo ""
echo "▶ 调用 mac_acceptance_v17_170_189.applescript（自动 ~15s · 目标进程 $APP_NAME）"
if [[ ! -f "$SCRIPT_DIR/mac_acceptance_v17_170_189.applescript" ]]; then
    echo "⚠️ 未找到 applescript · 退出"
    exit 1
fi
osascript "$SCRIPT_DIR/mac_acceptance_v17_170_189.applescript" "$SHOTS_DIR" "$APP_NAME" 2>&1 | tee "$OUT_DIR/capture.log"
OSA_RC=${PIPESTATUS[0]}
if (( OSA_RC != 0 )); then
    echo "❌ applescript 失败（rc=$OSA_RC）· 检查 $OUT_DIR/capture.log"
fi

# 关 app（cleanup 兜底再做一次）
echo ""
echo "关闭 app ..."
[[ -n "$APP_NAME" ]] && osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
sleep 1
kill "$APP_PID" 2>/dev/null || true
APP_PID=""

SHOT_COUNT=$(ls "$SHOTS_DIR" 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "════════════════════════════════════════════════════"
echo " ✅ 完成 · 截图 $SHOT_COUNT / 5"
echo "════════════════════════════════════════════════════"
date
