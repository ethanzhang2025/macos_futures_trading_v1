#!/usr/bin/env bash
# Mac 端集中验收自动化脚本（v15.82 累积 · v12.14 → v15.82 共 130+ batch）
#
# 用法（在 Mac 上）：
#   cd /Users/admin/Documents/MAC版本_期货交易终端/macos_futures_trading_v1
#   git pull
#   chmod +x mac_acceptance.sh
#   ./mac_acceptance.sh
#
# 流程：
#   Phase 1 (~30s)  · build + 全量 swift test
#   Phase 2 (~3min) · 启动 app · AppleScript 自动遍历 21 窗口快捷键 + 截图
#   Phase 3 (~30s)  · 数据契约 demo（自动）
#   Phase 4 (~10s)  · 打包 + scp 回 Linux beelink@vvsvr
#   Phase 5         · 输出用户辅助清单（手动验项）
#
# 输出：~/Desktop/mac_acceptance_v15.82/
#   ├─ 01_build.log
#   ├─ 02_test.log
#   ├─ 03_demo.log
#   ├─ shots/  (21+ PNG)
#   └─ summary.txt

set -uo pipefail

OUT_DIR="$HOME/Desktop/mac_acceptance_v15.82"
SHOTS_DIR="$OUT_DIR/shots"
BUILD_PATH="/tmp/mac_acc_v82"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_DIR="/home/beelink/debug_img/mac_acceptance_v15.82"
APP_PID=""

mkdir -p "$SHOTS_DIR"

# ─── 兜底上传函数（任何阶段退出都尝试上传）───
upload_results() {
    local rc=$?
    # 写一份 exit summary 让 Linux 端知道脚本走到哪里
    {
        echo "# Mac 切机验收 · 退出 summary · $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "## 退出码 / 阶段"
        echo "- 脚本退出码: $rc"
        echo "- 完成阶段: ${COMPLETED_PHASES:-未到 P1}"
        if [[ -n "${BUILD_RC:-}" ]]; then
            echo "- Build RC: $BUILD_RC $([[ $BUILD_RC -eq 0 ]] && echo '✅' || echo '❌')"
        fi
        if [[ -n "${TEST_RC:-}" ]]; then
            echo "- Test RC: $TEST_RC $([[ $TEST_RC -eq 0 ]] && echo '✅' || echo '❌')"
        fi
        echo ""
        echo "## 已生成文件"
        ls -la "$OUT_DIR" 2>/dev/null | sed 's/^/    /'
        if [[ -d "$SHOTS_DIR" ]]; then
            local n=$(ls "$SHOTS_DIR" 2>/dev/null | wc -l | tr -d ' ')
            echo ""
            echo "## 截图（共 $n 张）"
            ls "$SHOTS_DIR" 2>/dev/null | sort | sed 's/^/    /'
        fi
        echo ""
        echo "## 系统信息"
        echo "- macOS: $(sw_vers -productVersion 2>/dev/null || echo '?')"
        echo "- swift: $(swift --version 2>&1 | head -1 || echo '?')"
    } > "$OUT_DIR/exit_summary.txt"

    # 兜底关 app（如果还在跑）
    if [[ -n "$APP_PID" ]]; then
        kill "$APP_PID" 2>/dev/null || true
    fi
    osascript -e 'tell application "MainApp" to quit' 2>/dev/null || true
    osascript -e 'tell application "FuturesTerminal" to quit' 2>/dev/null || true

    # 尝试上传（任何情况都试）
    echo ""
    echo "▶ 上传当前所有结果（即使中途失败也传）→ beelink@vvsvr:$REMOTE_DIR"
    if ssh -o ConnectTimeout=5 beelink@vvsvr "echo ok" > /dev/null 2>&1; then
        ssh beelink@vvsvr "mkdir -p $REMOTE_DIR"
        scp -r "$OUT_DIR"/* beelink@vvsvr:"$REMOTE_DIR/" 2>&1 | tail -5
        echo "✅ 上传完成 · 远程: beelink@vvsvr:$REMOTE_DIR"
        echo ""
        echo "请告诉 Linux 端 Claude：「Mac 验收脚本退出码 $rc · 完成阶段 ${COMPLETED_PHASES:-未到 P1} · 看图」"
    else
        echo "⚠️ SSH 不通 · 手动 scp："
        echo "    scp -r $OUT_DIR beelink@vvsvr:~/debug_img/"
    fi
}
trap upload_results EXIT

COMPLETED_PHASES="开始"

echo "════════════════════════════════════════════════════"
echo " Mac 切机自动化验收 · v15.82 累积"
echo " 输出 → $OUT_DIR"
echo "════════════════════════════════════════════════════"
date

# ─── Phase 1: build + test ───
echo ""
echo "▶ Phase 1/5 · swift build + 全量 test（~30s）"
echo "────────────────────────────────────────────────────"
swift build --build-path "$BUILD_PATH" 2>&1 | tee "$OUT_DIR/01_build.log"
BUILD_RC=${PIPESTATUS[0]}

if [[ "$BUILD_RC" -ne 0 ]]; then
    echo "❌ Build 失败 · 中止后续 · trap 会自动上传 01_build.log + exit_summary.txt"
    # 提取关键错误行写到顶层（让远端 Claude 一眼看到）
    {
        echo "# BUILD 失败摘要"
        echo "## 错误行（grep error/warning · tail 50）"
        grep -nE "error:|warning:" "$OUT_DIR/01_build.log" 2>/dev/null | tail -50 || echo "未匹配到 error/warning 行"
        echo ""
        echo "## 末 80 行"
        tail -80 "$OUT_DIR/01_build.log"
    } > "$OUT_DIR/01_build_error_extract.txt"
    COMPLETED_PHASES="P1 build 失败"
    exit 1
fi
COMPLETED_PHASES="P1 build OK"

swift test --build-path "$BUILD_PATH" 2>&1 | tee "$OUT_DIR/02_test.log"
TEST_RC=${PIPESTATUS[0]}
COMPLETED_PHASES="P1 build+test 完成"

# 提取关键统计
TEST_SUMMARY=$(grep -E "Test run with|Executed [0-9]+ tests" "$OUT_DIR/02_test.log" | tail -3)

# 测试失败也继续跑（截图 / scp 都仍有价值）
if [[ "$TEST_RC" -ne 0 ]]; then
    echo "⚠️ Test 部分失败 · 继续跑后续 phase（截图仍有价值）"
    grep -nE "FAILED|❌|error:" "$OUT_DIR/02_test.log" 2>/dev/null | tail -30 > "$OUT_DIR/02_test_failures.txt"
fi

# ─── Phase 2: 启动 app + 自动截图 21 窗口 ───
echo ""
echo "▶ Phase 2/5 · 启动 app + 自动截图 21 窗口（~3min）"
echo "────────────────────────────────────────────────────"

# 后台启动 app
echo "启动 swift run MainApp ..."
nohup swift run MainApp --build-path "$BUILD_PATH" > "$OUT_DIR/02b_app_stdout.log" 2>&1 &
APP_PID=$!
echo "app pid = $APP_PID · 等待 8s 让 app 完全启动"
sleep 8

# 调用 AppleScript 遍历 21 窗口
if [[ ! -f "$SCRIPT_DIR/mac_acceptance_capture.applescript" ]]; then
    echo "⚠️ 未找到 mac_acceptance_capture.applescript（在 $SCRIPT_DIR）"
else
    osascript "$SCRIPT_DIR/mac_acceptance_capture.applescript" "$SHOTS_DIR" 2>&1 | tee "$OUT_DIR/02c_capture.log"
fi

# 关 app
echo "关闭 app ..."
osascript -e 'tell application "MainApp" to quit' 2>/dev/null || true
sleep 1
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true

SHOT_COUNT=$(ls "$SHOTS_DIR" 2>/dev/null | wc -l | tr -d ' ')
echo "截图完成 · $SHOT_COUNT 张"
COMPLETED_PHASES="P2 截图 $SHOT_COUNT 张"

# ─── Phase 3: 数据契约 demo ───
echo ""
echo "▶ Phase 3/5 · 数据契约 demo（无 UI · 命令行）"
echo "────────────────────────────────────────────────────"

# 找命令行 demo target（如果有）
DEMOS=()
for tool in SinaTickDemo SyncEngineDemo; do
    if swift build --build-path "$BUILD_PATH" --target "$tool" 2>/dev/null; then
        DEMOS+=("$tool")
    fi
done

{
    echo "# Phase 3 数据契约 demo"
    echo "# 时间：$(date)"
    echo ""
    if [[ "${#DEMOS[@]}" -eq 0 ]]; then
        echo "无可用 demo target（已搁置 SinaTickDemo / SyncEngineDemo）"
    fi
    # macOS 自带没有 GNU timeout · 用 perl alarm 包一层（兼容 Linux/Mac）
    run_with_timeout() {
        local secs=$1; shift
        perl -e 'alarm shift; exec @ARGV' "$secs" "$@"
    }
    for d in "${DEMOS[@]}"; do
        echo "──── $d ────"
        run_with_timeout 30 swift run --build-path "$BUILD_PATH" "$d" 2>&1 | head -50
        echo ""
    done
} > "$OUT_DIR/03_demo.log"
COMPLETED_PHASES="P3 demo 完成"

# ─── Phase 4: 写 summary（scp 由 trap 兜底执行）───
echo ""
echo "▶ Phase 4/5 · 写 summary"
echo "────────────────────────────────────────────────────"

{
    echo "# Mac 切机验收 summary · $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "## 1. Build / Test"
    echo "- Build RC: $BUILD_RC"
    echo "- Test RC: $TEST_RC"
    echo "- 测试关键行："
    echo "$TEST_SUMMARY" | sed 's/^/    /'
    echo ""
    echo "## 2. 截图"
    echo "- shots 目录：$SHOTS_DIR"
    echo "- 数量：$SHOT_COUNT"
    if [[ "$SHOT_COUNT" -gt 0 ]]; then
        echo "- 文件列表："
        ls "$SHOTS_DIR" | sort | sed 's/^/    /'
    fi
    echo ""
    echo "## 3. demo"
    if [[ "${#DEMOS[@]}" -eq 0 ]]; then
        echo "- 无可用 demo（不影响验收）"
    else
        echo "- 已跑：${DEMOS[*]}"
    fi
    echo ""
    echo "## 4. 系统信息"
    echo "- macOS: $(sw_vers -productVersion 2>/dev/null || echo '?')"
    echo "- Xcode: $(xcodebuild -version 2>/dev/null | head -1 || echo '未安装')"
    echo "- swift: $(swift --version 2>&1 | head -1 || echo '?')"
} > "$OUT_DIR/summary.txt"
COMPLETED_PHASES="P4 summary 完成"

# scp 由 trap upload_results 兜底执行 · 这里不再重复

# ─── Phase 5: 用户辅助清单 ───
echo ""
echo "════════════════════════════════════════════════════"
echo " ✅ 自动化验收完成（P1-P4 · trap 接管 P5 上传）"
echo "════════════════════════════════════════════════════"
echo ""
echo "▶ Phase 5/5 · 用户辅助验收（必须手动 · ~20 分钟）"
echo ""
echo "请打开主目录下的 [Mac切机用户辅助清单_v15.82.md]"
echo "按清单走完后告诉 Linux 端 Claude（或截图回报）"
echo ""
echo "本机结果路径：$OUT_DIR"
echo "远程路径：beelink@vvsvr:$REMOTE_DIR"
COMPLETED_PHASES="P5 自动化全部完成 · 等用户辅助"
echo ""
date
