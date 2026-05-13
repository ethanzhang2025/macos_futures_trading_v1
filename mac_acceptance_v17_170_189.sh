#!/usr/bin/env bash
# v17.170-189 增量验收 · swift test + 5 项主图 overlay 半自动截图
#
# 半自动模式（v17.192 改版）：
#   脚本启动 app + 跑 test · 截图阶段每张图都等你回车确认
#   你自己手动按快捷键 + 看到 overlay/sheet 出来后回车 · 脚本立即 screencapture
#   完全消除 applescript 焦点丢失 / 快捷键没生效 / 盲截无效问题
#
# 用法：
#   ./mac_acceptance_v17_170_189.sh              # 全跑（test + 半自动截图）
#   ./mac_acceptance_v17_170_189.sh --skip-test  # 跳过 test 直接截图
#   ./mac_acceptance_v17_170_189.sh --skip-shots # 仅跑 test

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${HOME}/Desktop/mac_acceptance_v17_170_189"
SHOTS_DIR="${OUT_DIR}/shots"
REMOTE_DIR="/tmp/mac_acceptance_v17_170_189"
BUILD_PATH="/tmp/build_v1730_b1"

SKIP_TEST=0
SKIP_SHOTS=0
for arg in "$@"; do
    case "${arg}" in
        --skip-test)  SKIP_TEST=1 ;;
        --skip-shots) SKIP_SHOTS=1 ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    esac
done

APP_PID=""
APP_NAME=""

detect_app_name() {
    local n
    for n in MainApp FuturesTerminal; do
        if pgrep -x "${n}" > /dev/null 2>&1; then
            echo "${n}"
            return 0
        fi
    done
    return 1
}

cleanup() {
    local rc=$?
    if [[ -n "${APP_PID}" ]]; then
        kill "${APP_PID}" 2>/dev/null || true
    fi
    [[ -n "${APP_NAME}" ]] && osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null || true
    osascript -e 'tell application "MainApp" to quit' 2>/dev/null || true
    osascript -e 'tell application "FuturesTerminal" to quit' 2>/dev/null || true

    local n
    n=$(ls "${SHOTS_DIR}" 2>/dev/null | wc -l | tr -d ' ')
    {
        echo "# v17.170-189 增量验收结果"
        echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "退出码: ${rc}"
        echo "截图数: ${n} / 5"
        echo "macOS:  $(sw_vers -productVersion 2>/dev/null)"
        echo "swift:  $(swift --version 2>&1 | head -1)"
        echo ""
        echo "--- 截图列表 ---"
        ls "${SHOTS_DIR}" 2>/dev/null | sort | sed 's/^/  /'
        echo ""
        echo "--- app_stdout.log 末尾 80 行（用于诊断 crash） ---"
        tail -80 "${OUT_DIR}/app_stdout.log" 2>/dev/null
    } > "${OUT_DIR}/summary.txt"

    if ssh -o ConnectTimeout=5 beelink@vvsvr "echo ok" > /dev/null 2>&1; then
        ssh beelink@vvsvr "rm -rf ${REMOTE_DIR} && mkdir -p ${REMOTE_DIR}"
        scp -q "${OUT_DIR}/summary.txt" beelink@vvsvr:"${REMOTE_DIR}/" 2>/dev/null || true
        [[ -f "${OUT_DIR}/app_stdout.log" ]] && scp -q "${OUT_DIR}/app_stdout.log" beelink@vvsvr:"${REMOTE_DIR}/" 2>/dev/null || true
        [[ -f "${OUT_DIR}/swift_test.log" ]] && scp -q "${OUT_DIR}/swift_test.log" beelink@vvsvr:"${REMOTE_DIR}/" 2>/dev/null || true
        [[ -d "${SHOTS_DIR}" ]] && scp -rq "${SHOTS_DIR}" beelink@vvsvr:"${REMOTE_DIR}/" 2>/dev/null || true
        echo "✅ scp 完成 · 告诉 Linux 端: rc=${rc} N=${n}"
    else
        echo "⚠️ SSH 不通 · 手动 scp: scp -r ${OUT_DIR} beelink@vvsvr:${REMOTE_DIR}/"
    fi
}
trap cleanup EXIT

mkdir -p "${SHOTS_DIR}"
rm -f "${SHOTS_DIR}"/*.png 2>/dev/null

# capture_step <name> <prompt>
# 极简：回车 → screencapture -i → 用户鼠标点窗口/拖框 → 完成
capture_step() {
    local name="$1"
    local prompt="$2"
    local target="${SHOTS_DIR}/${name}.png"

    echo ""
    echo "📸 ${name} · ${prompt}"
    read -p "▸ 回车截图 / s 跳过 / q 退出: " ans
    case "${ans}" in
        s|S) echo "  ⏭  跳过"; return 0 ;;
        q|Q) exit 0 ;;
    esac
    rm -f "${target}" 2>/dev/null
    screencapture -i -o "${target}"
    if [[ -f "${target}" ]]; then
        echo "  ✅ ${name}.png ($(stat -f '%z' "${target}") bytes)"
    else
        echo "  ⚠️ 取消"
    fi
}

echo "════════════════════════════════════════════════════"
echo " v17.170-189 增量验收 · 半自动模式（v17.192 改版）"
echo " 输出 -> ${OUT_DIR}"
echo " skip_test=${SKIP_TEST} skip_shots=${SKIP_SHOTS}"
echo "════════════════════════════════════════════════════"
date

# Phase 0: swift test
if (( SKIP_TEST == 0 )); then
    echo ""
    echo "▶ Phase 0: swift test --build-path ${BUILD_PATH}"
    swift test --build-path "${BUILD_PATH}" 2>&1 | tee "${OUT_DIR}/swift_test.log" | tail -20
    TEST_RC=${PIPESTATUS[0]}
    if (( TEST_RC != 0 )); then
        echo "❌ swift test 失败 rc=${TEST_RC} 检查 ${OUT_DIR}/swift_test.log"
        exit 10
    fi
    echo "✅ swift test 全绿"
fi

if (( SKIP_SHOTS == 1 )); then
    echo ""
    echo "▶ --skip-shots 已设 · 截图阶段跳过"
    exit 0
fi

# Phase 1: 启动 app（不再轮询 · 让用户控制节奏）
echo ""
echo "▶ Phase 1: 启动 swift run MainApp"
nohup swift run MainApp --build-path "${BUILD_PATH}" > "${OUT_DIR}/app_stdout.log" 2>&1 &
APP_PID=$!
echo "swift run pid = ${APP_PID}"
echo ""
echo "⏳ 等 MainApp 启动 +  ⌘N 开主图 + 主图数据加载完毕"
echo "   （等到 chart 上 K 线 + HUD + 价格 全部正常显示再继续）"
read -p "▸ 主图准备好后按 [回车] 进入截图流程: " _

if APP_NAME=$(detect_app_name); then
    echo "✓ 探测到进程 ${APP_NAME}"
else
    echo "⚠️ 未探测到 MainApp / FuturesTerminal 进程 · 但继续（也许进程名不同）"
fi

# Phase 2: 半自动截图 5 张
echo ""
echo "═══════════════════════════════════════════════"
echo " Phase 2: 5 张截图 · 每张前手动操作 + 回车截图"
echo "═══════════════════════════════════════════════"

capture_step "24_v17188_patterns_overlay" \
    "操作：在主图按 ⌘⇧P 打开【形态识别 overlay】(13 种形态高亮)"

capture_step "25_v17182_patterns_list_sheet" \
    "操作：先 ⌘⇧P 关掉 overlay · 再按 ⌘⇧L 打开【形态清单 sheet】(含 stats 区)"

capture_step "26_v17180_resonance_overlay_hud" \
    "操作：先 ESC 关掉 sheet · 再按 ⌘⇧Y 打开【多周期共振 overlay + 左上 HUD】"

capture_step "27_v17184_resonance_stats_sheet" \
    "操作：保持共振 overlay 开 · 再按 ⌘⌥⇧Y 打开【共振历史回测 sheet】"

capture_step "28_v17189_secondary_picker_sheet" \
    "操作：ESC 关 sheet + ⌘⇧Y 关共振 · 再按 ⌘⌥G 打开【多合约 overlay picker sheet】"

# 关 app
echo ""
echo "关闭 app"
[[ -n "${APP_NAME}" ]] && osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null || true
sleep 1
kill "${APP_PID}" 2>/dev/null || true
APP_PID=""

SHOT_COUNT=$(ls "${SHOTS_DIR}" 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "════════════════════════════════════════════════════"
echo " ✅ 完成 截图 ${SHOT_COUNT} / 5"
echo "════════════════════════════════════════════════════"
date
