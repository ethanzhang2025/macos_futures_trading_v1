#!/usr/bin/env bash
# 快捷键诊断 · 判断 macOS 系统/其它 app 是否占用某个快捷键
#
# 用法：
#   ./check_shortcut.sh "⌘⇧L"     # 检查 cmd-shift-L
#   ./check_shortcut.sh "cmd+shift+l"
#   ./check_shortcut.sh            # 列我们项目用到的全部快捷键
#
# 输出：
#   1. 系统全局占用（com.apple.symbolichotkeys）
#   2. MainApp menu bar 上是否显示这个 shortcut（间接验证 app 是否注册）
#   3. 提示用户人工验证步骤

set -uo pipefail

PROJECT_SHORTCUTS=(
    "⌘N|主图新建窗口"
    "⌘⇧P|形态识别 overlay toggle"
    "⌘⇧L|形态清单 sheet（v17.165）"
    "⌘⇧Y|多周期共振 overlay toggle（v17.170）"
    "⌘⌥⇧Y|共振历史回测 sheet（v17.184）"
    "⌘⌥G|多合约 overlay picker（v17.189）"
    "⌘⌥L|跨合约联动窗口"
    "⌘⇧W|swing 标注 toggle"
    "⌘⇧S|支撑阻力 overlay toggle"
    "⌘⇧M|测距三态"
    "⌘⌥R|回放复盘窗口"
    "⌘⌥J|交易日志窗口"
)

show_known() {
    echo "═══ 项目已绑定的全部快捷键 ═══"
    for entry in "${PROJECT_SHORTCUTS[@]}"; do
        printf "  %-12s  %s\n" "${entry%|*}" "${entry#*|}"
    done
    echo ""
    echo "用法：./check_shortcut.sh \"⌘⇧L\"  # 单独诊断某个"
}

probe_system_shortcuts() {
    local target="$1"
    echo ""
    echo "═══ ① macOS 系统全局占用扫描 ═══"
    echo "目标：${target}"
    echo ""

    # 系统快捷键 plist · 找有没有相同 modifier+key
    local plist="${HOME}/Library/Preferences/com.apple.symbolichotkeys.plist"
    if [[ -f "${plist}" ]]; then
        echo "--- com.apple.symbolichotkeys 启用的全部全局热键（id + key + modifiers）---"
        defaults read com.apple.symbolichotkeys 2>/dev/null \
            | awk '/AppleSymbolicHotKeys/,/^}/' \
            | grep -E '^\s+[0-9]+\s*=|enabled = 1|parameters' \
            | head -60
        echo ""
        echo "(modifiers 数字含义：⌘=1048576 ⇧=131072 ⌥=524288 ⌃=262144 · 多个相加)"
    else
        echo "未找到 ${plist}"
    fi

    echo ""
    echo "═══ ② MainApp menu bar 是否注册该快捷键（间接验证）═══"
    echo "操作步骤："
    echo "  1. 在 Mac 端启动 MainApp（swift run MainApp）"
    echo "  2. 主图打开后 · 点 menu bar 顶部各菜单（File/Edit/View/工具/Window）"
    echo "  3. 扫菜单项右侧是否显示「${target}」"
    echo "  4. 显示出来 = .commands 注册的全局 shortcut（menu 截获优先于 view）"
    echo "  5. 没显示 = view 内 .keyboardShortcut 绑定（依赖 chart window 是 keyWindow）"
    echo ""

    echo "═══ ③ 人工最终验证 ═══"
    echo "  在主图按 ${target} → 看现象："
    echo "    a) HUD 出'XX：显示/隐藏'  = state 改了 · 快捷键 OK · 渲染问题（看代码 binding）"
    echo "    b) sheet 弹出           = 完全 OK"
    echo "    c) 完全无反应           = 快捷键被截获 或 view binding 不在焦点窗口"
    echo "    d) 系统'duo' 错误音      = 系统/其他 app 占用中"
    echo ""
}

if (( $# == 0 )); then
    show_known
    exit 0
fi

probe_system_shortcuts "$1"
