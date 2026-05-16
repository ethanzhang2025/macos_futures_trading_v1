#!/bin/bash
# mac_loop.sh · Mac 端全自动 UI 测试闭环 · v17.252+
#
# 用户工作流（每次开发循环）：
#   cd <repo>
#   git pull --ff-only && ./mac_loop.sh
#
# 8 步:
#   1. 环境自检 + venv setup（首次自动建 · 后续秒过）
#   2. (用户已 git pull · 脚本不重复)
#   3. ./run-mac.sh debug build → MainApp.app
#   4. 启 appium server (background · trap 自动 kill)
#   5. pytest ui_tests/generated/ --json-report
#   6. 收集 result.json / shots / logs
#   7. scp → vvsvr:/home/beelink/debug_img/appium_loop_latest/
#   8. cleanup

set -euo pipefail

# ─── 参数解析 ──────────────────────────────────────
# --until N  : 只跑 test_step_00 ~ test_step_NN (例: --until 02)
# --step N   : 只跑 test_step_NN (单步)
# (无参)     : 跑 generated/ 内全部测试
UNTIL=""
SINGLE_STEP=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --until) UNTIL="$2"; shift 2 ;;
        --step)  SINGLE_STEP="$2"; shift 2 ;;
        -h|--help)
            echo "用法: $0 [--until NN] [--step NN]"
            echo "  --until 02   只跑 step_00 + step_01 + step_02"
            echo "  --step 01    只跑 step_01 单步"
            echo "  (无参)        跑全部 generated/"
            exit 0
            ;;
        *) shift ;;
    esac
done

cd "$(dirname "$0")"
REPO_DIR="$(pwd)"
TESTS_DIR="$REPO_DIR/ui_tests"
VENV_DIR="$TESTS_DIR/.venv"
SHOTS_DIR="$TESTS_DIR/shots"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_OUT="/tmp/appium_loop_${TIMESTAMP}"
APPIUM_LOG="/tmp/appium_${TIMESTAMP}.log"

VVSVR_REMOTE="beelink@vvsvr"
VVSVR_PATH="/home/beelink/debug_img/appium_loop_latest"

APPIUM_PID=""

cleanup() {
    # v17.259 · 顺序: 先停自动化测试 (appium + child procs) · 再退主程序 (MainApp)
    # 解决: appium fork 多个 node child + WebDriverAgent · 只 kill 父 PID 残留挂住 shell

    # 1. 停 appium server + 所有相关 child 进程
    if [[ -n "${APPIUM_PID:-}" ]] && kill -0 "$APPIUM_PID" 2>/dev/null; then
        echo "   ↓ 停 appium server (PID=$APPIUM_PID)"
        kill -TERM "$APPIUM_PID" 2>/dev/null || true
        sleep 1
        kill -9 "$APPIUM_PID" 2>/dev/null || true
    fi
    # 兜底 · pkill 残留 appium / WebDriverAgent / mac2-driver 进程
    pkill -f "appium --base-path" 2>/dev/null || true
    pkill -f "WebDriverAgent" 2>/dev/null || true
    pkill -f "appium-mac2-driver" 2>/dev/null || true

    # 2. 关 MainApp · SIGTERM 让它走完正常退出流程 (清 ChartScene Metal / 释放窗口)
    if pgrep -f "MainApp.app/Contents/MacOS/MainApp" >/dev/null 2>&1; then
        echo "   ↓ 关 MainApp (graceful SIGTERM)"
        pkill -TERM -f "MainApp.app/Contents/MacOS/MainApp" 2>/dev/null || true
        sleep 2
        # 兜底 force kill (如果 graceful 卡住)
        if pgrep -f "MainApp.app/Contents/MacOS/MainApp" >/dev/null 2>&1; then
            echo "   ↓ MainApp 未响应 · force kill (SIGKILL)"
            pkill -9 -f "MainApp.app/Contents/MacOS/MainApp" 2>/dev/null || true
        fi
    fi
}
trap cleanup EXIT INT TERM

sep() { echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
sep
echo "  mac_loop · 全自动 UI 测试闭环 · $TIMESTAMP"
sep
echo ""

# ─── [1/8] 环境自检 + 自动 setup ──────────────────────────
echo "🔍 [1/8] 环境自检..."

if ! command -v node >/dev/null 2>&1; then
    echo "❌ node 未装 · 跑: brew install node"; exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "❌ python3 未装 · 跑: brew install python@3.11"; exit 1
fi
if ! command -v appium >/dev/null 2>&1; then
    echo "❌ appium 未装 · 跑:"
    echo "     npm install -g appium"
    echo "     appium driver install mac2"
    exit 1
fi
## appium 输出带 ANSI 颜色码 · grep 不要锚定行首 · 同时合并 stderr
if ! appium driver list --installed 2>&1 | grep -q "mac2"; then
    echo "📦 mac2 driver 未装 · 自动装..."
    appium driver install mac2 || {
        echo "   (driver install 报错 · 通常是已装 · 跳过)"
    }
fi

# Python venv（首次创建 · 后续直接激活）
if [[ ! -d "$VENV_DIR" ]]; then
    echo "📦 首次创建 Python venv: $VENV_DIR"
    python3 -m venv "$VENV_DIR"
fi
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

# 装 / 更新 deps（pip 自己跳过已装的）
"$VENV_DIR/bin/pip" install -q --upgrade pip
"$VENV_DIR/bin/pip" install -q -r "$TESTS_DIR/requirements.txt"

echo "✅ 环境就绪 (node $(node -v) / python $(python3 -V 2>&1 | awk '{print $2}') / appium $(appium -v))"
echo ""

# ─── [2/8] git 状态确认（用户已 pull）──────────────────────
echo "📥 [2/8] 验证 git 状态..."
HEAD=$(git rev-parse --short HEAD)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "   HEAD = $HEAD  branch = $BRANCH"
echo ""

# ─── [3/8] 构建 .app bundle ─────────────────────────────
echo "🔨 [3/8] 构建 MainApp.app..."
./run-mac.sh debug build
BIN_PATH=$(swift build --show-bin-path -c debug)
APP_PATH="$BIN_PATH/MainApp.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ .app 未生成: $APP_PATH"; exit 1
fi
echo "   .app: $APP_PATH"
echo ""

# ─── [4/8] 启 appium server (background) ─────────────────
echo "🚀 [4/8] 启 Appium server..."
appium --base-path /wd/hub --log-level warn > "$APPIUM_LOG" 2>&1 &
APPIUM_PID=$!
echo "   appium PID = $APPIUM_PID · log = $APPIUM_LOG"

# 等 ready (最多 20s)
APPIUM_READY=false
for i in {1..20}; do
    if curl -sf "http://127.0.0.1:4723/wd/hub/status" >/dev/null 2>&1; then
        echo "   appium ready (${i}s)"
        APPIUM_READY=true
        break
    fi
    sleep 1
done
if ! $APPIUM_READY; then
    echo "❌ appium 启动超时 · 看 $APPIUM_LOG"
    tail -30 "$APPIUM_LOG"
    exit 1
fi
echo ""

# ─── [5/8] 跑 pytest ────────────────────────────────────
echo "🧪 [5/8] 跑 pytest..."
mkdir -p "$SHOTS_DIR"
rm -f "$TESTS_DIR/result.json" "$TESTS_DIR/pytest.log"
rm -f "$TESTS_DIR"/ui_tree_*.xml

export APP_PATH
export APPIUM_URL="http://127.0.0.1:4723/wd/hub"

cd "$TESTS_DIR"

# 计算要跑的测试文件列表
if [[ -n "$SINGLE_STEP" ]]; then
    TEST_FILES=$(ls generated/test_step_${SINGLE_STEP}_*.py 2>/dev/null || true)
    echo "   → 单步模式 · 跑 step_$SINGLE_STEP"
elif [[ -n "$UNTIL" ]]; then
    # 取所有 step_*.py · 按数字排序 · 取前 (UNTIL+1) 个
    LIMIT=$((10#$UNTIL + 1))
    TEST_FILES=$(ls generated/test_step_*.py 2>/dev/null | sort | head -n "$LIMIT" | tr '\n' ' ')
    echo "   → 渐进模式 · 跑 step_00 ~ step_$UNTIL ($LIMIT 个文件)"
else
    TEST_FILES="generated/"
    echo "   → 全量模式 · 跑 generated/ 内全部"
fi

if [[ -z "$TEST_FILES" ]]; then
    echo "❌ 未找到匹配的测试文件 · 检查 --step / --until 参数"
    exit 1
fi

# pytest 即使失败也继续后续步骤 · 用 || true
# --maxfail=1 让第一个 fail 立即停 · 不浪费时间
"$VENV_DIR/bin/python3" -m pytest $TEST_FILES \
    --json-report --json-report-file=result.json \
    --maxfail=1 \
    -v --tb=short 2>&1 | tee pytest.log || true
cd "$REPO_DIR"

echo ""

# ─── [6/8] 收集产出 ──────────────────────────────────────
echo "📊 [6/8] 收集结果 → $RESULTS_OUT"
mkdir -p "$RESULTS_OUT"

cp "$TESTS_DIR/result.json" "$RESULTS_OUT/" 2>/dev/null || echo "   ⚠️ result.json 缺失"
cp "$TESTS_DIR/pytest.log"  "$RESULTS_OUT/" 2>/dev/null || true
cp "$APPIUM_LOG"            "$RESULTS_OUT/appium.log" 2>/dev/null || true
cp -r "$SHOTS_DIR"          "$RESULTS_OUT/" 2>/dev/null || true
cp "$TESTS_DIR"/ui_tree_*.xml "$RESULTS_OUT/" 2>/dev/null || true

cat > "$RESULTS_OUT/summary.txt" <<EOF
mac_loop · $TIMESTAMP
branch: $BRANCH
HEAD:   $HEAD
APP_PATH: $APP_PATH

== shots/ ==
$(ls -la "$SHOTS_DIR" 2>/dev/null | tail -n +2 || echo "  (无)")

== ui_tree dumps ==
$(ls "$TESTS_DIR"/ui_tree_*.xml 2>/dev/null || echo "  (无)")
EOF

echo ""

# ─── [7/8] scp → vvsvr ──────────────────────────────────
echo "📤 [7/8] scp → $VVSVR_REMOTE:$VVSVR_PATH"
if ssh -o ConnectTimeout=5 "$VVSVR_REMOTE" \
        "mkdir -p '$VVSVR_PATH' && rm -rf '$VVSVR_PATH'/*" 2>/dev/null; then
    scp -rq "$RESULTS_OUT"/* "$VVSVR_REMOTE:$VVSVR_PATH/" \
        && echo "   ✅ 已上传" \
        || echo "   ⚠️ scp 部分失败 · 结果保留在: $RESULTS_OUT"
else
    echo "   ⚠️ SSH 不通 vvsvr · 结果保留在: $RESULTS_OUT"
fi
echo ""

# ─── [8/8] cleanup ──────────────────────────────────────
echo "🧹 [8/8] cleanup..."
cleanup
deactivate 2>/dev/null || true

# 解析 pytest 结果 · 打个简短 summary
if [[ -f "$RESULTS_OUT/result.json" ]]; then
    PASS=$(grep -o '"passed":[0-9]*' "$RESULTS_OUT/result.json" | head -1 | cut -d: -f2 || echo "?")
    FAIL=$(grep -o '"failed":[0-9]*' "$RESULTS_OUT/result.json" | head -1 | cut -d: -f2 || echo "?")
    SKIP=$(grep -o '"skipped":[0-9]*' "$RESULTS_OUT/result.json" | head -1 | cut -d: -f2 || echo "?")
    echo ""
    echo "   📊 pytest: ✅ $PASS pass / ❌ $FAIL fail / ⏭️  $SKIP skip"
fi

echo ""
sep
echo "  ✅ mac_loop done · 告诉 Claude: ./pull_results.sh"
sep
