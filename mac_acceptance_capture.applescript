-- Mac 端 21+ 窗口自动遍历 + 截图（v15.82 累积验收）
--
-- 用法：osascript mac_acceptance_capture.applescript /path/to/shots
--
-- 流程：循环每个窗口 → 用 AppleScript 模拟键盘快捷键 → 等 0.7s 渲染
--      → screencapture -m -o shots/NN_window.png（截当前主屏 · 不弹光标）
--      → cmd+w 关窗 → 下一个
--
-- 注意：app 需要预先 activate · 由 mac_acceptance.sh 启动后立即调用本脚本

on run argv
    if (count of argv) < 1 then
        log "用法：osascript mac_acceptance_capture.applescript <shots_dir>"
        return
    end if
    set shotsDir to item 1 of argv

    -- 21 窗口列表：{seq, name, modifiers, key}
    -- modifiers：c=command, s=shift, o=option(alt)
    -- 注意：变量名避开 AppleScript 保留字（windows / window 是 every window 的 selector）
    set winList to {¬
        {"01", "chart_main", "c", "n"}, ¬
        {"02", "watchlist", "c", "l"}, ¬
        {"03", "review", "c", "r"}, ¬
        {"04", "alert", "c", "b"}, ¬
        {"05", "journal", "c", "j"}, ¬
        {"06", "workspace", "c", "k"}, ¬
        {"07", "trading_simnow", "c", "t"}, ¬
        {"08", "training_paper", "cs", "t"}, ¬
        {"09", "multichart", "co", "m"}, ¬
        {"10", "spread_cross", "co", "s"}, ¬
        {"11", "option", "co", "o"}, ¬
        {"12", "sector", "co", "b"}, ¬
        {"13", "heatmap", "co", "h"}, ¬
        {"14", "position", "co", "p"}, ¬
        {"15", "correlation", "co", "c"}, ¬
        {"16", "moneyflow", "co", "n"}, ¬
        {"17", "calendar_spread", "co", "x"}, ¬
        {"18", "dashboard", "co", "i"}, ¬
        {"19", "session_compare", "co", "t"}, ¬
        {"20", "anomaly_monitor", "co", "a"}, ¬
        {"21", "spread_alert", "co", "w"}, ¬
        {"22", "formula_editor", "co", "f"}, ¬
        {"23", "wh_import", "cs", "i"} ¬
    }

    -- 让 app 前置（按可执行名找）
    try
        tell application "System Events" to set frontmost of (first process whose name is "MainApp") to true
    on error
        try
            tell application "System Events" to set frontmost of (first process whose name is "FuturesTerminal") to true
        on error
            log "⚠️ 未找到 MainApp / FuturesTerminal 进程 · 退出"
            return
        end try
    end try
    delay 1.0

    repeat with w in winList
        set seq to item 1 of w
        set winName to item 2 of w
        set mods to item 3 of w
        set keyStr to item 4 of w

        log "▶ [" & seq & "] " & winName & " · " & mods & "+" & keyStr

        -- 先关闭可能挡视野的辅助 sheet（按 esc）
        tell application "System Events" to key code 53 -- esc
        delay 0.2

        -- 模拟快捷键
        if mods is "c" then
            tell application "System Events" to keystroke keyStr using {command down}
        else if mods is "cs" then
            tell application "System Events" to keystroke keyStr using {command down, shift down}
        else if mods is "co" then
            tell application "System Events" to keystroke keyStr using {command down, option down}
        else if mods is "cso" then
            tell application "System Events" to keystroke keyStr using {command down, shift down, option down}
        end if

        -- 等渲染（行情/board 类窗口需要更久 · 主图加载真行情 ~2s）
        delay 2.0

        -- screencapture -l <window-id>：只截当前 frontmost 窗口（不含 dock / 后台 app）
        -- 拿 frontmost window id（System Events 的 window id 与 screencapture 不同 · 用 AppKit 路径）
        set outPath to shotsDir & "/" & seq & "_" & winName & ".png"
        try
            -- 获取 frontmost app 的 window id（screencapture -l 兼容格式）
            set winID to do shell script "osascript -e 'tell application \"System Events\" to tell (first process whose frontmost is true) to id of front window'"
            do shell script "screencapture -x -o -l " & winID & " " & quoted form of outPath
        on error
            -- fallback 整屏（极少数情况下找不到 window id · 比如 sheet 状态）
            do shell script "screencapture -x -o " & quoted form of outPath
        end try

        delay 0.2
    end repeat

    log "✅ 全 " & (count of winList) & " 窗口截图完成"
end run
