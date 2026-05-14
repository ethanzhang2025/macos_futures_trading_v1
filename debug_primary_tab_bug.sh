#!/usr/bin/env bash
# debug_primary_tab_bug.sh · 半自动复现 PrimaryTab 切换 bug · 一张一张模式
#
# 用户反馈（2026-05-14）：5 个一级 tab（看盘/套利/期权/复盘/训练）· 点后面几个时
# 顶部 PrimaryTabBar + WorkspaceTabBar 整体消失（"找不到标题 tab"）· 且无法切回
#
# Root cause（v17.207 已修）：18 个子窗口的 .frame(minWidth/minHeight) 在 Shell 嵌入时
# 强行撑大 PaneBody · 把 ShellWindow 顶部 PrimaryTabBar/WorkspaceTabBar 挤出可见
#
# 用法：
#   ./debug_primary_tab_bug.sh                # 全跑 6 张（修后应该可以一次跑完）
#   ./debug_primary_tab_bug.sh --reset --shot 1   # 推荐：清 cache 重启 + 截单张
#   ./debug_primary_tab_bug.sh --reset --shot 3   # 清 cache · 用户进入期权后截
#   ./debug_primary_tab_bug.sh --skip-run --shot 4  # 跳启动 · app 已在跑 · 仅截
#
# --reset 行为：
#   1. quit MainApp（如果在跑）
#   2. defaults delete MainApp shell.v1.primaryTab  → app 启动默认看盘
#   3. swift run 重启 → 进入默认 .watching
#   4. 用户自己切到目标 PrimaryTab + 回车 → screencapture

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${HOME}/Desktop/debug_primary_tab_bug"
SHOTS_DIR="${OUT_DIR}/shots"
REMOTE_DIR="/tmp/debug_primary_tab_bug"
BUILD_PATH="/tmp/build_v1730_b1"

SKIP_RUN=0
RESET_CACHE=0
ONLY_SHOT=""
prev_arg=""
for arg in "$@"; do
    case "${prev_arg}" in
        --shot) ONLY_SHOT="${arg}"; prev_arg=""; continue ;;
    esac
    case "${arg}" in
        --skip-run) SKIP_RUN=1 ;;
        --reset) RESET_CACHE=1 ;;
        --shot) prev_arg="${arg}" ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    esac
done

want_shot() {
    [[ -z "${ONLY_SHOT}" ]] && return 0
    case ",${ONLY_SHOT}," in
        *",$1,"*) return 0 ;;
    esac
    return 1
}

APP_PID=""

cleanup() {
    local rc=$?
    if [[ -n "${APP_PID}" ]]; then
        kill "${APP_PID}" 2>/dev/null || true
    fi
    osascript -e 'tell application "MainApp" to quit' 2>/dev/null || true

    # 生成 summary
    local n
    n=$(ls "${SHOTS_DIR}" 2>/dev/null | wc -l | tr -d ' ')
    {
        echo "# PrimaryTab 切换 bug 复现"
        echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "退出码: ${rc}"
        echo "截图数: ${n} / 6"
        echo "macOS:  $(sw_vers -productVersion 2>/dev/null)"
        echo "git:    $(cd "${SCRIPT_DIR}" && git log --oneline -1 2>/dev/null)"
        echo ""
        echo "--- 截图列表 ---"
        ls -la "${SHOTS_DIR}" 2>/dev/null | sort | sed 's/^/  /'
        echo ""
        echo "--- UserDefaults shell.v1.* dump ---"
        cat "${OUT_DIR}/userdefaults.txt" 2>/dev/null
        echo ""
        echo "--- app_stdout.log 末尾 60 行 ---"
        tail -60 "${OUT_DIR}/app_stdout.log" 2>/dev/null
    } > "${OUT_DIR}/summary.txt"

    if ssh -o ConnectTimeout=5 beelink@vvsvr "echo ok" > /dev/null 2>&1; then
        ssh beelink@vvsvr "rm -rf ${REMOTE_DIR} && mkdir -p ${REMOTE_DIR}"
        scp -q "${OUT_DIR}/summary.txt" beelink@vvsvr:"${REMOTE_DIR}/" 2>/dev/null || true
        [[ -f "${OUT_DIR}/userdefaults.txt" ]] && scp -q "${OUT_DIR}/userdefaults.txt" beelink@vvsvr:"${REMOTE_DIR}/" 2>/dev/null || true
        [[ -f "${OUT_DIR}/app_stdout.log" ]] && scp -q "${OUT_DIR}/app_stdout.log" beelink@vvsvr:"${REMOTE_DIR}/" 2>/dev/null || true
        [[ -d "${SHOTS_DIR}" ]] && scp -rq "${SHOTS_DIR}" beelink@vvsvr:"${REMOTE_DIR}/" 2>/dev/null || true
        echo "✅ scp 完成 · vvsvr:${REMOTE_DIR}"
    else
        echo "⚠️ SSH 不通 · 手动 scp: scp -r ${OUT_DIR} beelink@vvsvr:${REMOTE_DIR}/"
    fi
}
trap cleanup EXIT

mkdir -p "${SHOTS_DIR}"
rm -f "${SHOTS_DIR}"/*.png 2>/dev/null

# capture_step <name> <prompt>
capture_step() {
    local name="$1"
    local prompt="$2"
    local target="${SHOTS_DIR}/${name}.png"

    echo ""
    echo "📸 ${name}"
    echo "  ${prompt}"
    read -p "▸ 回车截图 / s 跳过 / q 退出: " ans
    case "${ans}" in
        s|S) echo "  ⏭  跳过"; return 0 ;;
        q|Q) exit 0 ;;
    esac
    rm -f "${target}" 2>/dev/null
    # 相机模式：点窗口截整窗 · 推荐点 ShellWindow 顶半部（带 PrimaryTabBar + WorkspaceTabBar）
    screencapture -iW -o "${target}"
    if [[ -f "${target}" ]]; then
        echo "  ✅ ${name}.png ($(stat -f '%z' "${target}") bytes)"
    else
        echo "  ⚠️ 取消"
    fi
}

echo "════════════════════════════════════════════════════"
echo " PrimaryTab 切换 bug 复现脚本"
echo " 输出 -> ${OUT_DIR}"
echo "════════════════════════════════════════════════════"
date

# Phase 0: reset cache（可选 · 清 shell.v1.primaryTab 让 app 启动默认 .watching）
if (( RESET_CACHE == 1 )); then
    echo ""
    echo "▶ Phase 0: --reset · 清 shell.v1.primaryTab + 重启 app 进默认看盘"
    osascript -e 'tell application "MainApp" to quit' 2>/dev/null || true
    pkill -f MainApp 2>/dev/null || true
    sleep 1
    # 清 PrimaryTab UserDefault（保留其他 workspace 配置）
    defaults delete MainApp "shell.v1.primaryTab" 2>/dev/null || true
    defaults delete MainApp "shell.v1.activeWorkspaceID" 2>/dev/null || true
    echo "✓ shell.v1.primaryTab / activeWorkspaceID 已清"
    # 仍走 Phase 1 启动
    SKIP_RUN=0
fi

# Phase 1: 启动 app
if (( SKIP_RUN == 0 )); then
    echo ""
    echo "▶ Phase 1: pkill 旧 MainApp + 启动新（增量编译）"
    pkill -f MainApp 2>/dev/null || true
    sleep 1
    nohup swift run MainApp --build-path "${BUILD_PATH}" > "${OUT_DIR}/app_stdout.log" 2>&1 &
    APP_PID=$!
    echo "swift run pid = ${APP_PID}"
    echo ""
    echo "⏳ 等 MainApp 启动 + Shell 主窗口出现 + 左 Sidebar / 顶 PrimaryTabBar / WorkspaceTabBar 全部正常显示"
    read -p "▸ Shell 窗口就绪后按 [回车] 进入截图: " _
else
    echo "▶ --skip-run · 跳过启动 · 假设 app 已运行"
fi

# Phase 2: 6 张半自动截图
echo ""
echo "═══════════════════════════════════════════════"
echo " Phase 2: 半自动 6 张截图"
echo " 每张截图前：在 Shell 主窗口里操作 · 完成后回到终端回车"
echo " 截图模式：相机光标 · 点 Shell 主窗口截整窗（推荐截顶半部 · 含 2 个 TabBar）"
echo "═══════════════════════════════════════════════"

want_shot 1 && capture_step "1_默认看盘_workspace_tabs" \
    "默认状态（看盘 PrimaryTab）· 看 顶部 PrimaryTabBar 5 个一级模块 + WorkspaceTabBar 显示几个 workspace tab（应该有 1+ 个 · 「看盘 N」名字）"

want_shot 2 && capture_step "2_点击套利后" \
    "在 PrimaryTabBar 上【点击「套利」】· 等 1 秒让 SwiftUI 重渲染 · 截图看：① 顶 PrimaryTabBar 5 个 tab 是否还在 ② WorkspaceTabBar 显示什么"

want_shot 3 && capture_step "3_点击期权后" \
    "在 PrimaryTabBar 上【点击「期权」】· 等 1 秒 · 截图看 PrimaryTabBar + WorkspaceTabBar 状态"

want_shot 4 && capture_step "4_点击复盘后" \
    "在 PrimaryTabBar 上【点击「复盘」】· 等 1 秒 · 截图看 PrimaryTabBar + WorkspaceTabBar 状态"

want_shot 5 && capture_step "5_点击训练后" \
    "在 PrimaryTabBar 上【点击「训练」】· 等 1 秒 · 截图看 PrimaryTabBar + WorkspaceTabBar 状态"

want_shot 6 && capture_step "6_点回看盘后" \
    "在 PrimaryTabBar 上【点回「看盘」】· 等 1 秒 · 截图看 PrimaryTabBar + WorkspaceTabBar 状态（应该恢复初始 workspace tabs）"

# Phase 3: dump UserDefaults
echo ""
echo "▶ Phase 3: dump UserDefaults shell.v1.*"
{
    echo "=== UserDefaults · MainApp / FuturesTerminal ==="
    echo ""
    for bundle in com.example.MainApp com.example.FuturesTerminal MainApp FuturesTerminal; do
        echo "--- domain: ${bundle} ---"
        defaults read "${bundle}" 2>/dev/null | head -200
        echo ""
    done
    echo ""
    echo "=== 全 NSGlobalDomain 含 shell.v1 / chartTheme ==="
    defaults read NSGlobalDomain 2>/dev/null | grep -A1 -i "shell\|chart\|workspace\|primary" | head -80
} > "${OUT_DIR}/userdefaults.txt"
echo "✅ userdefaults.txt dump 完成（行数：$(wc -l < "${OUT_DIR}/userdefaults.txt")）"

# Phase 4: 关 app
echo ""
echo "关闭 app"
osascript -e 'tell application "MainApp" to quit' 2>/dev/null || true
sleep 1
kill "${APP_PID}" 2>/dev/null || true
APP_PID=""

SHOT_COUNT=$(ls "${SHOTS_DIR}" 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "════════════════════════════════════════════════════"
echo " ✅ 完成 截图 ${SHOT_COUNT} / 6"
echo "════════════════════════════════════════════════════"
date
