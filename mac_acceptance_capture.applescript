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
        log "用法：osascript mac_acceptance_capture.applescript <shots_dir> [filter]"
        log "  filter 例：'all'（默认）/ '03' / '03,07,21'"
        return
    end if
    set shotsDir to item 1 of argv
    set filterArg to "all"
    if (count of argv) >= 2 then set filterArg to item 2 of argv
    -- filter 包装成 ",NN," 格式便于 contains 查询
    set filterPadded to "," & filterArg & ","

    -- 23 窗口列表：{seq, name, modifiers, key, delay_seconds}
    -- modifiers：c=command, s=shift, o=option(alt)
    -- delay：依据数据源 · 真行情 4s · mock 1.5s · 复杂渲染 2.5s
    -- 注意：变量名避开 AppleScript 保留字（windows / window）
    set winList to {¬
        {"01", "chart_main", "c", "n", 4.0}, ¬
        {"02", "watchlist", "c", "l", 3.0}, ¬
        {"03", "review", "c", "r", 2.5}, ¬
        {"04", "alert", "c", "b", 2.0}, ¬
        {"05", "journal", "c", "j", 2.0}, ¬
        {"06", "workspace", "c", "k", 2.0}, ¬
        {"07", "trading_simnow", "c", "t", 2.0}, ¬
        {"08", "training_paper", "cs", "t", 2.0}, ¬
        {"09", "multichart", "co", "m", 4.0}, ¬
        {"10", "spread_cross", "co", "s", 2.5}, ¬
        {"11", "option", "co", "o", 2.5}, ¬
        {"12", "sector", "co", "b", 1.5}, ¬
        {"13", "heatmap", "co", "h", 1.5}, ¬
        {"14", "position", "co", "p", 1.5}, ¬
        {"15", "correlation", "co", "c", 2.0}, ¬
        {"16", "moneyflow", "co", "n", 1.5}, ¬
        {"17", "calendar_spread", "co", "x", 2.5}, ¬
        {"18", "dashboard", "co", "i", 2.5}, ¬
        {"19", "session_compare", "co", "t", 2.0}, ¬
        {"20", "anomaly_monitor", "co", "a", 2.0}, ¬
        {"21", "spread_alert", "co", "w", 2.0}, ¬
        {"22", "formula_editor", "co", "f", 1.5}, ¬
        {"23", "wh_import", "cs", "i", 1.5} ¬
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

    set capturedCount to 0
    repeat with w in winList
        set seq to item 1 of w
        set winName to item 2 of w
        set mods to item 3 of w
        set keyStr to item 4 of w
        set winDelay to item 5 of w

        set shouldRun to true
        if filterArg is not "all" then
            if filterPadded does not contain ("," & seq & ",") then set shouldRun to false
        end if

        if shouldRun then
            log "▶ [" & seq & "] " & winName & " · " & mods & "+" & keyStr & " · delay " & winDelay & "s"
            set capturedCount to capturedCount + 1

            tell application "System Events" to key code 53
            delay 0.2

            if mods is "c" then
                tell application "System Events" to keystroke keyStr using {command down}
            else if mods is "cs" then
                tell application "System Events" to keystroke keyStr using {command down, shift down}
            else if mods is "co" then
                tell application "System Events" to keystroke keyStr using {command down, option down}
            else if mods is "cso" then
                tell application "System Events" to keystroke keyStr using {command down, shift down, option down}
            end if

            -- 按窗口数据源动态等渲染（真行情 4s / 复杂 2.5s / mock 1.5s）
            delay winDelay

            set outPath to shotsDir & "/" & seq & "_" & winName & ".png"
            do shell script "screencapture -x -o " & quoted form of outPath

            delay 0.2
        else
            log "⏭️  [" & seq & "] " & winName & " 跳过（filter）"
        end if
    end repeat

    log "✅ 截图完成 · 实跑 " & capturedCount & " / " & (count of winList) & " 窗口"
end run
