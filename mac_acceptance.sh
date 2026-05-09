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

mkdir -p "$SHOTS_DIR"

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
    echo "❌ Build 失败 · 中止后续"
    exit 1
fi

swift test --build-path "$BUILD_PATH" 2>&1 | tee "$OUT_DIR/02_test.log"
TEST_RC=${PIPESTATUS[0]}

# 提取关键统计
TEST_SUMMARY=$(grep -E "Test run with|Executed [0-9]+ tests" "$OUT_DIR/02_test.log" | tail -3)

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
    for d in "${DEMOS[@]}"; do
        echo "──── $d ────"
        timeout 30 swift run --build-path "$BUILD_PATH" "$d" 2>&1 | head -50
        echo ""
    done
} > "$OUT_DIR/03_demo.log"

# ─── Phase 4: 写 summary + scp ───
echo ""
echo "▶ Phase 4/5 · 写 summary + 上传到 Linux"
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

# scp 上传
REMOTE_DIR="/home/beelink/debug_img/mac_acceptance_v15.82"
if ssh -o ConnectTimeout=5 beelink@vvsvr "echo ok" > /dev/null 2>&1; then
    echo "scp → beelink@vvsvr:$REMOTE_DIR"
    ssh beelink@vvsvr "rm -rf $REMOTE_DIR && mkdir -p $REMOTE_DIR"
    scp -r "$OUT_DIR"/* beelink@vvsvr:"$REMOTE_DIR/" 2>&1 | tail -5
    echo "✅ 上传完成"
else
    echo "⚠️ SSH 不通 · 跳过上传 · 用户手动 scp"
    echo "    scp -r $OUT_DIR beelink@vvsvr:~/debug_img/"
fi

# ─── Phase 5: 用户辅助清单 ───
echo ""
echo "════════════════════════════════════════════════════"
echo " ✅ 自动化验收完成"
echo "════════════════════════════════════════════════════"
echo ""
echo "▶ Phase 5/5 · 用户辅助验收（必须手动 · ~20 分钟）"
echo ""
echo "请打开主目录下的 [Mac切机用户辅助清单_v15.82.md]"
echo "按清单走完后告诉 Linux 端 Claude（或截图回报）"
echo ""
echo "本机结果路径：$OUT_DIR"
[[ -n "${REMOTE_DIR:-}" ]] && echo "远程路径：beelink@vvsvr:$REMOTE_DIR"
echo ""
date
