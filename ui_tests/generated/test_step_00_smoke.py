"""Step 00 · Smoke · 验证 .app 启动 + driver 连接 + 1 张截图

最快的健康检查（< 15s）· 不切窗口 · 不点菜单 · 只 verify app launched。
通过 = mac_loop 闭环 ok。

✗ 失败排查: appium 没起 / .app 没 build / driver 连不上 / Mac 权限不足
"""
from __future__ import annotations
from pathlib import Path

from helpers import screenshot, dump_ui_tree, wait_seconds


def test_smoke_app_launched(driver, shots_dir):
    tests_root = Path(shots_dir).resolve().parent

    # 等 cold start 完成（首屏渲染）
    wait_seconds(2)

    # 1 张截图 + 1 张 ui_tree dump · 仅此
    screenshot(driver, shots_dir, "step_00_smoke")
    dump_ui_tree(driver, str(tests_root / "ui_tree_step_00.xml"))

    # 验证: app title = 期货终端 · 至少有 1 个 window
    windows = driver.find_elements("class name", "XCUIElementTypeWindow")
    assert len(windows) >= 1, f"未检测到任何 NSWindow · 见 ui_tree_step_00.xml"

    # 拿第一个 window 的 title · 至少不是空（app 真启动了）
    title = ""
    try:
        title = windows[0].get_attribute("title") or ""
    except Exception:
        pass
    assert title, f"第 1 个 window title 为空 · app 可能没真启动"
