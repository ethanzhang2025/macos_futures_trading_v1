#!/usr/bin/env bash
# Mac 端集中验收自动化脚本（v15.82+ 累积 · v12.14 → 当前 130+ batch）
#
# 用法（在 Mac 上）：
#   cd /Users/admin/Documents/MAC版本_期货交易终端/macos_futures_trading_v1
#   git pull
#   chmod +x mac_acceptance.sh
#
# 模式：
#   ./mac_acceptance.sh                  # 全自动（build + test + 23 截图 + demo + scp）
#   ./mac_acceptance.sh --shots 03       # 仅重跑 03 截图（隐含跳过 build/test）
#   ./mac_acceptance.sh --shots 03,07,21 # 多个
#   ./mac_acceptance.sh --shots 03-08    # 范围
#   ./mac_acceptance.sh --skip-build     # 跳过 build/test · 走完截图流程
#   ./mac_acceptance.sh --skip-test      # 仅跳过 test（build 仍跑）
#   ./mac_acceptance.sh --skip-shots     # 跳过 Phase 2 截图（23 窗口已验过 · 仅验编译/测试）
#   ./mac_acceptance.sh --help           # 显示帮助
#
# 输出：~/Desktop/mac_acceptance_v15.82/

set -uo pipefail

# ─── 参数解析 ───
SHOTS_FILTER="all"
SKIP_BUILD=false
SKIP_TEST=false
SKIP_DEMO=false
SKIP_SHOTS=false

show_help() {
    sed -n '2,18p' "$0" | sed 's/^# \?//'
    exit 0
}

# 把 "03,07-09,12" 展开为 "03,07,08,09,12"
expand_filter() {
    local input="$1"
    [[ "$input" == "all" ]] && { echo "all"; return; }
    local out=""
    IFS=',' read -ra parts <<< "$input"
    for p in "${parts[@]}"; do
        if [[ "$p" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local s=${BASH_REMATCH[1]}; local e=${BASH_REMATCH[2]}
            for i in $(seq "$s" "$e"); do
                out+="$(printf '%02d' $((10#$i))),"
            done
        else
            out+="$(printf '%02d' $((10#$p))),"
        fi
    done
    echo "${out%,}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --shots)      SHOTS_FILTER=$(expand_filter "$2"); SKIP_BUILD=true; SKIP_TEST=true; SKIP_DEMO=true; shift 2 ;;
        --skip-build) SKIP_BUILD=true; SKIP_TEST=true; shift ;;  # 跳 build 必跳 test
        --skip-test)  SKIP_TEST=true; shift ;;
        --skip-demo)  SKIP_DEMO=true; shift ;;
        --skip-shots) SKIP_SHOTS=true; shift ;;
        --help|-h)    show_help ;;
        *) echo "❌ 未知参数: $1"; echo "  用 --help 看帮助"; exit 1 ;;
    esac
done

OUT_DIR="$HOME/Desktop/mac_acceptance_v15.82"
SHOTS_DIR="$OUT_DIR/shots"
BUILD_PATH="/tmp/mac_acc_v82"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_DIR="/home/beelink/debug_img/mac_acceptance_v15.82"
APP_PID=""

mkdir -p "$SHOTS_DIR"

# ─── 按阶段精选上传文件（节省 token · 不传无关大文件）───
#
# 策略：
#   - 总传 exit_summary.txt（小 · 一目了然）
#   - P1 build 失败 → 只传 01_build_error_extract.txt（精简）
#   - test 失败 → 只传 02_test_failures.txt（精简）· 不传 02_test.log 全量（500KB+）
#   - 截图失败 → 传 02c_capture.log + 02b_app_stdout_tail.txt
#   - P5 全 OK → 传 shots/ + summary.txt（不传 build/test 详情）
#   - demo log 永远小（< 1KB）· 总传
upload_results() {
    local rc=$?
    local phase="${COMPLETED_PHASES:-未到 P1}"

    # ── 判断是否是脚本启动早期失败（连 P1 都没进）──
    local early_abort=false
    if [[ "$phase" == "开始" ]] || [[ "$phase" == "未到 P1" ]]; then
        early_abort=true
    fi

    # ── exit_summary.txt（总传 · ≤ 1KB）──
    {
        echo "# Mac 切机验收 · 退出 summary · $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        if $early_abort; then
            echo "🚨 脚本启动即失败 · 未进入任何 phase"
            echo "退出码: $rc"
            echo "可能原因：bash 语法错 / 未定义变量 / 编辑引入非 ASCII 字符（v15.84+ 曾遇到）"
        else
            echo "退出码: $rc · 阶段: $phase"
        fi
        [[ -n "${BUILD_RC:-}" ]] && echo "Build RC: $BUILD_RC $([[ $BUILD_RC -eq 0 ]] && echo '✅' || echo '❌')"
        [[ -n "${TEST_RC:-}" ]]  && echo "Test RC:  $TEST_RC $([[ $TEST_RC -eq 0 ]] && echo '✅' || echo '❌')"
        if [[ -d "$SHOTS_DIR" ]]; then
            local n=$(ls "$SHOTS_DIR" 2>/dev/null | wc -l | tr -d ' ')
            echo "截图: $n 张"
        fi
        echo "macOS: $(sw_vers -productVersion 2>/dev/null) · swift: $(swift --version 2>&1 | head -1 | awk -F'version' '{print $NF}' | awk '{print $1}')"
    } > "$OUT_DIR/exit_summary.txt"

    # 兜底关 app（如果还在跑）
    if [[ -n "$APP_PID" ]]; then
        kill "$APP_PID" 2>/dev/null || true
    fi
    osascript -e 'tell application "MainApp" to quit' 2>/dev/null || true
    osascript -e 'tell application "FuturesTerminal" to quit' 2>/dev/null || true

    # ── 决定上传文件清单（按阶段精选）──
    local upload_list=("exit_summary.txt")

    # P1 build 失败：只传精简错误
    if [[ "$phase" == *"build 失败"* ]]; then
        [[ -f "$OUT_DIR/01_build_error_extract.txt" ]] && upload_list+=("01_build_error_extract.txt")
    fi

    # test 失败：精简 fail context（不传 02_test.log 全量 500KB+）
    if [[ "${TEST_RC:-0}" -ne 0 ]] && [[ -f "$OUT_DIR/02_test.log" ]]; then
        # 提取 swift testing ✘ + Expectation failed + 末尾统计 + 上下 5 行
        {
            echo "# Test 失败精简（02_test.log 总 $(wc -l < "$OUT_DIR/02_test.log" | tr -d ' ') 行）"
            echo ""
            echo "## 失败 case"
            grep -nE "✘|Expectation failed|recorded an issue" "$OUT_DIR/02_test.log" | head -40
            echo ""
            echo "## 末尾统计"
            grep -E "Test run with|Executed [0-9]+ tests" "$OUT_DIR/02_test.log" | tail -5
        } > "$OUT_DIR/02_test_failures_extract.txt"
        upload_list+=("02_test_failures_extract.txt")
    fi

    # P2 截图阶段：失败时传 capture log + app stdout tail
    if [[ -f "$OUT_DIR/02c_capture.log" ]]; then
        local shot_n=$(ls "$SHOTS_DIR" 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$shot_n" -lt 20 ]]; then
            upload_list+=("02c_capture.log")
            # app stdout 末 50 行（看启动是否正常 · 不传全量 15KB warning）
            if [[ -f "$OUT_DIR/02b_app_stdout.log" ]]; then
                tail -50 "$OUT_DIR/02b_app_stdout.log" > "$OUT_DIR/02b_app_stdout_tail.txt"
                upload_list+=("02b_app_stdout_tail.txt")
            fi
        fi
    fi

    # demo log（永远 < 1KB · 总传）
    [[ -f "$OUT_DIR/03_demo.log" ]] && upload_list+=("03_demo.log")

    # P5 全 OK：传 shots/ + summary
    if [[ "$phase" == *"P5"* ]] || [[ "$phase" == *"P4 summary 完成"* ]]; then
        [[ -f "$OUT_DIR/summary.txt" ]] && upload_list+=("summary.txt")
        local shot_n=$(ls "$SHOTS_DIR" 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$shot_n" -gt 0 ]]; then
            upload_list+=("shots")
        fi
    fi

    # ── 上传 ──
    echo ""
    if $early_abort; then
        echo "🚨 脚本启动即失败 · 仅上传 exit_summary（远端 Claude 看错误信息）"
    else
        echo "▶ 上传精选文件（${#upload_list[@]} 项）→ beelink@vvsvr:${REMOTE_DIR}"
    fi
    if ssh -o ConnectTimeout=5 beelink@vvsvr "echo ok" > /dev/null 2>&1; then
        ssh beelink@vvsvr "rm -rf ${REMOTE_DIR} && mkdir -p ${REMOTE_DIR}"
        for f in "${upload_list[@]}"; do
            if [[ -e "$OUT_DIR/$f" ]]; then
                scp -rq "$OUT_DIR/$f" beelink@vvsvr:"${REMOTE_DIR}/" && echo "  ✓ $f"
            fi
        done
        if $early_abort; then
            echo ""
            echo "❌ 脚本根本没启动 · 远端 Claude 看 exit_summary.txt 定位错误"
            echo "请告诉 Linux 端：「脚本启动失败 · 退出码 ${rc} · 看 exit_summary」"
        else
            echo "✅ 上传完成 · 本地完整日志保留：$OUT_DIR"
            echo "请告诉 Linux 端 Claude：「Mac 验收脚本退出码 ${rc} · 完成阶段 ${phase} · 看图」"
        fi
    else
        echo "⚠️ SSH 不通 · 手动 scp 精选："
        for f in "${upload_list[@]}"; do
            echo "    scp -r $OUT_DIR/$f beelink@vvsvr:${REMOTE_DIR}/"
        done
    fi
}
trap upload_results EXIT

COMPLETED_PHASES="开始"

echo "════════════════════════════════════════════════════"
echo " Mac 切机自动化验收 · v15.82+"
echo " 模式：$([ "${SHOTS_FILTER}" != "all" ] && echo "仅截图 [${SHOTS_FILTER}]" || echo "全自动")"
echo " 跳过：$([ "$SKIP_BUILD" = true ] && echo "build " || echo "")$([ "$SKIP_TEST" = true ] && echo "test " || echo "")$([ "$SKIP_SHOTS" = true ] && echo "shots " || echo "")$([ "$SKIP_DEMO" = true ] && echo "demo" || echo "")"
echo " 输出 → $OUT_DIR"
echo "════════════════════════════════════════════════════"
date

# ─── Phase 1: build + test（可跳过）───
TEST_SUMMARY=""
if [[ "$SKIP_BUILD" = true ]]; then
    echo ""
    echo "⏭️  Phase 1/5 跳过（--skip-build · 默认走 incremental build path = ${BUILD_PATH}）"
    BUILD_RC=0
    TEST_RC=0
    COMPLETED_PHASES="P1 跳过"
else
    echo ""
    echo "▶ Phase 1/5 · swift build + 全量 test（~30s）"
    echo "────────────────────────────────────────────────────"
    swift build --build-path "$BUILD_PATH" 2>&1 | tee "$OUT_DIR/01_build.log"
    BUILD_RC=${PIPESTATUS[0]}

    if [[ "$BUILD_RC" -ne 0 ]]; then
        echo "❌ Build 失败 · 中止后续 · trap 上传精简 extract（不传 01_build.log）"
        # v17.190 · error 行 + 周围 3 行 context（含 note: 解释真根 · token ~3KB）
        {
            echo "# BUILD 失败 · error 行 + 上下文 3 行（含 note:）"
            grep -nE "\.swift:[0-9]+:[0-9]+: error:" "$OUT_DIR/01_build.log" 2>/dev/null \
                | head -30 \
                | while IFS=: read -r linenum _; do
                    awk -v ln="$linenum" 'NR>=ln && NR<=ln+3' "$OUT_DIR/01_build.log"
                    echo "---"
                  done \
                | sed 's|.*/Sources/|Sources/|'
        } > "$OUT_DIR/01_build_error_extract.txt"
        COMPLETED_PHASES="P1 build 失败"
        exit 1
    fi
    COMPLETED_PHASES="P1 build OK"

    if [[ "$SKIP_TEST" = true ]]; then
        echo "⏭️  swift test 跳过（--skip-test）"
        TEST_RC=0
    else
        swift test --build-path "$BUILD_PATH" 2>&1 | tee "$OUT_DIR/02_test.log"
        TEST_RC=${PIPESTATUS[0]}
        TEST_SUMMARY=$(grep -E "Test run with|Executed [0-9]+ tests" "$OUT_DIR/02_test.log" | tail -3)
    fi
    COMPLETED_PHASES="P1 build+test 完成"
fi

# 测试失败也继续跑（截图 / scp 都仍有价值）
if [[ "$TEST_RC" -ne 0 ]]; then
    echo "⚠️ Test 部分失败 · 继续跑后续 phase（截图仍有价值）"
    grep -nE "FAILED|❌|error:" "$OUT_DIR/02_test.log" 2>/dev/null | tail -30 > "$OUT_DIR/02_test_failures.txt"
fi

# ─── Phase 2: 启动 app + 自动截图 ───
echo ""
if [[ "$SKIP_SHOTS" = true ]]; then
    echo "⏭️  Phase 2/5 跳过截图（--skip-shots · 23 窗口框架已在前次切机验过）"
    SHOT_COUNT=$(ls "$SHOTS_DIR" 2>/dev/null | wc -l | tr -d ' ')
    COMPLETED_PHASES="P2 截图跳过（保留历史 $SHOT_COUNT 张）"
else
    if [[ "$SHOTS_FILTER" == "all" ]]; then
        echo "▶ Phase 2/5 · 启动 app + 自动截图 23 窗口（~3min）"
    else
        echo "▶ Phase 2/5 · 启动 app + 仅截图 [${SHOTS_FILTER}]（~$(echo "${SHOTS_FILTER}" | tr ',' '\n' | wc -l | tr -d ' ')×8s）"
        # filter 模式只清掉指定的 shots（保留其他历史）· 而非整个 SHOTS_DIR
        IFS=',' read -ra FILT_SEQS <<< "$SHOTS_FILTER"
        for s in "${FILT_SEQS[@]}"; do
            rm -f "$SHOTS_DIR"/${s}_*.png 2>/dev/null || true
        done
    fi
    echo "────────────────────────────────────────────────────"

    # 后台启动 app（必须 · 截图依赖运行中的 app）
    echo "启动 swift run MainApp ..."
    nohup swift run MainApp --build-path "$BUILD_PATH" > "$OUT_DIR/02b_app_stdout.log" 2>&1 &
    APP_PID=$!
    # app 冷启动 ~6s · Sina 真行情首次拉取 ~3s · 留 12s 让首图 K 线就位（macOS 26 + Xcode 26 增量编译开销）
    echo "app pid = $APP_PID · 等待 12s 让 app 完全启动 + Sina 首次拉取就位"
    sleep 12

    # 调用 AppleScript（filter 第二参数）
    if [[ ! -f "$SCRIPT_DIR/mac_acceptance_capture.applescript" ]]; then
        echo "⚠️ 未找到 mac_acceptance_capture.applescript（在 ${SCRIPT_DIR}）"
    else
        osascript "$SCRIPT_DIR/mac_acceptance_capture.applescript" "$SHOTS_DIR" "$SHOTS_FILTER" 2>&1 | tee "$OUT_DIR/02c_capture.log"
    fi

    # 关 app
    echo "关闭 app ..."
    osascript -e 'tell application "MainApp" to quit' 2>/dev/null || true
    sleep 1
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true

    SHOT_COUNT=$(ls "$SHOTS_DIR" 2>/dev/null | wc -l | tr -d ' ')
    echo "截图完成 · 当前 $SHOT_COUNT 张"
    COMPLETED_PHASES="P2 截图 $SHOT_COUNT 张"
fi

# ─── Phase 3: 数据契约 demo（可跳过）───
echo ""
if [[ "$SKIP_DEMO" = true ]]; then
    echo "⏭️  Phase 3/5 跳过（--skip-demo / 仅截图模式）"
else
    echo "▶ Phase 3/5 · 数据契约 demo（无 UI · 命令行）"
    echo "────────────────────────────────────────────────────"
    DEMOS=()
    for tool in SinaTickDemo SyncEngineDemo; do
        if swift build --build-path "$BUILD_PATH" --target "$tool" 2>/dev/null; then
            DEMOS+=("$tool")
        fi
    done
    {
        echo "# Phase 3 数据契约 demo · 时间：$(date)"
        echo ""
        if [[ "${#DEMOS[@]}" -eq 0 ]]; then
            echo "无可用 demo target"
        fi
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
fi
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
