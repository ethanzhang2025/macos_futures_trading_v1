"""Step 01 · 切 V1 主工作台 + 验证窗口 identifier

依赖: step_00 通过（说明 driver / app 链路 OK）
操作: 工具菜单 → 「🆕 主工作台 V1 · AppKit（⌘⌃1）」
验证: 存在 NSWindow identifier 含 "mainV1"

预计 < 10s · 1 张截图 1 张 dump。
"""
from __future__ import annotations
from pathlib import Path

import pytest

from helpers import (
    click_menu_item, screenshot, dump_ui_tree,
    find_window_by_id, wait_seconds,
)


def test_open_v1_main_window(driver, shots_dir):
    tests_root = Path(shots_dir).resolve().parent

    # 工具菜单 → 主工作台 V1
    click_menu_item(driver, "工具", "🆕 主工作台 V1 · AppKit（⌘⌃1）")
    wait_seconds(3)  # V1 主窗 cold init

    screenshot(driver, shots_dir, "step_01_v1_main")
    dump_ui_tree(driver, str(tests_root / "ui_tree_step_01.xml"))

    # 验证: V1 主窗已开（identifier 含 "mainV1"）
    try:
        win = find_window_by_id(driver, "mainV1", timeout=3)
    except AssertionError as e:
        pytest.fail(f"V1 主窗未出现 · {e} · 看 ui_tree_step_01.xml")

    title = win.get_attribute("title") or ""
    assert "主工作台 V1" in title or "mainV1" in title, \
        f"窗口找到但 title 不对: {title!r}"
