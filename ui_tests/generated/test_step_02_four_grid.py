"""Step 02 · 切四宫格 layout

依赖: step_01 通过（V1 主窗已开）
操作: 视图菜单 → 「V1 主窗面板布局」 → 「⊞ 四宫格」
验证: 四宫格 layout 切换后 UI tree 元素数显著增加（>= 1500 行）
      也是 5.1 节 bug 的关键复现点

预计 < 5s · 1 张截图 1 张 dump。
"""
from __future__ import annotations
from pathlib import Path

import pytest

from helpers import (
    click_menu_item, screenshot, dump_ui_tree, wait_seconds,
)


def test_switch_to_four_grid(driver, shots_dir):
    tests_root = Path(shots_dir).resolve().parent

    # 视图菜单 → V1 主窗面板布局 → ⊞ 四宫格
    try:
        click_menu_item(driver, "视图", "V1 主窗面板布局", "⊞ 四宫格")
    except AssertionError as e:
        pytest.fail(f"切四宫格菜单 click 失败 · {e}")

    wait_seconds(1.5)  # layout 切换 + 4 个 ChartScene 渲染

    screenshot(driver, shots_dir, "step_02_four_grid")
    dump_path = tests_root / "ui_tree_step_02.xml"
    dump_ui_tree(driver, str(dump_path))

    # 验证: ui_tree 元素数 >= 1500 行（四宫格状态比 V1 空主窗丰富很多）
    line_count = sum(1 for _ in open(dump_path, encoding="utf-8"))
    assert line_count >= 1500, (
        f"ui_tree 仅 {line_count} 行 · 期望 >= 1500 · 四宫格可能没生效 · 看 step_02_four_grid.png"
    )
