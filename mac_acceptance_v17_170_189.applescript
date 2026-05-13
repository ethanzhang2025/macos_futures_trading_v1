-- v17.170-189 增量验收 · 主图内 5 个快捷键 overlay/sheet 自动截图
--
-- 前置：mac_acceptance_v17_170_189.sh 已 nohup swift run MainApp & sleep 12 + ⌘N 开 chart 完成
--
-- 验证序列（每步：触发 → wait → screencapture → ESC/恢复）
--   24 · 形态识别 overlay（⌘⇧P · 默认关 → 开 → 截图 → 关）
--   25 · 形态清单 sheet（⌘⇧L · 含 stats 区 · 截图 → ESC）
--   26 · 多周期共振 overlay + HUD（⌘⇧Y · 默认关 → 开 → 截图 → 关）
--   27 · 共振历史回测 sheet（⌘⌥⇧Y · 截图 → ESC）
--   28 · 多合约 overlay picker sheet（⌘⌥G · 截图 → ESC）

on run argv
    if (count of argv) < 1 then
        log "用法：osascript mac_acceptance_v17_170_189.applescript <shots_dir> [app_name]"
        error "missing shots_dir" number 64
    end if
    set shotsDir to item 1 of argv
    set appName to "MainApp"
    if (count of argv) ≥ 2 then set appName to item 2 of argv

    -- 强制把目标 app 前置 · 找不到 = hard error 让 sh 端 exit
    try
        tell application "System Events" to set frontmost of (first process whose name is appName) to true
    on error errMsg
        log "❌ 目标进程 " & appName & " 未找到 · " & errMsg
        error "app process not found: " & appName number 70
    end try
    delay 1.0

    -- 二次确认窗口存在
    try
        tell application "System Events"
            set winCount to count of windows of (first process whose name is appName)
        end tell
        if winCount < 1 then
            log "❌ " & appName & " 窗口数 = 0 · 主窗口未渲染"
            error "no window for " & appName number 71
        end if
    end try

    -- 打开主图（⌘N · 数据加载 ~5s）
    tell application "System Events" to keystroke "n" using {command down}
    delay 5.0

    -- 24 · ⌘⇧P 形态识别 overlay
    tell application "System Events" to keystroke "p" using {command down, shift down}
    delay 1.2
    do shell script "screencapture -x -o " & quoted form of (shotsDir & "/24_v17188_patterns_overlay.png")
    delay 0.3
    -- 关掉再开下一项
    tell application "System Events" to keystroke "p" using {command down, shift down}
    delay 0.3

    -- 25 · ⌘⇧L 形态清单 sheet（含 v17.182 stats 区）
    tell application "System Events" to keystroke "l" using {command down, shift down}
    delay 1.5
    do shell script "screencapture -x -o " & quoted form of (shotsDir & "/25_v17182_patterns_list_sheet.png")
    delay 0.3
    tell application "System Events" to key code 53  -- ESC 关 sheet
    delay 0.5

    -- 26 · ⌘⇧Y 多周期共振 overlay + 左上 HUD
    tell application "System Events" to keystroke "y" using {command down, shift down}
    delay 1.5
    do shell script "screencapture -x -o " & quoted form of (shotsDir & "/26_v17180_resonance_overlay_hud.png")
    delay 0.3

    -- 27 · ⌘⌥⇧Y 共振历史回测 sheet（保留 overlay 开 · 让 sheet 数据有源）
    tell application "System Events" to keystroke "y" using {command down, shift down, option down}
    delay 1.5
    do shell script "screencapture -x -o " & quoted form of (shotsDir & "/27_v17184_resonance_stats_sheet.png")
    delay 0.3
    tell application "System Events" to key code 53
    delay 0.5
    -- 关掉共振 overlay
    tell application "System Events" to keystroke "y" using {command down, shift down}
    delay 0.3

    -- 28 · ⌘⌥G 多合约 overlay picker sheet
    tell application "System Events" to keystroke "g" using {command down, option down}
    delay 1.5
    do shell script "screencapture -x -o " & quoted form of (shotsDir & "/28_v17189_secondary_picker_sheet.png")
    delay 0.3
    tell application "System Events" to key code 53
    delay 0.3

    log "✅ v17.170-189 增量截图完成 · 5 张"
end run
