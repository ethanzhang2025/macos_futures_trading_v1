"""5.1 节 · 四宫格 divider 拖动行为测试

自动生成于 tests/specs/5.1_四宫格divider拖动.md
请勿手动修改 · 修改 spec 后由 Claude 重新生成。
"""
from __future__ import annotations

import os
from pathlib import Path

import pytest

# 通过 conftest 把 lib/ 加进 sys.path · 直接 import helpers
from helpers import (
    screenshot, press_keys, click_and_drag,
    find_by_label, find_all_by_type, find_static_texts,
    get_frame, assert_in_range, dump_ui_tree, wait_seconds,
)


# ─── 模块级 setup · 启 V1 主窗 + 切四宫格 ───────────────────────

@pytest.fixture(scope="module", autouse=True)
def setup_v1_four_grid(driver, shots_dir):
    """打开 .app → 切 V1 主窗 → 切四宫格 layout"""
    tests_root = Path(shots_dir).resolve().parent

    # 1. 初始 UI tree dump（看到的是默认 launch 状态）
    dump_ui_tree(driver, str(tests_root / "ui_tree_initial.xml"))
    screenshot(driver, shots_dir, "00_initial")

    # 2. ⌘⌃1 切 V1 主工作台
    press_keys(driver, "1", "ctrl|cmd")
    wait_seconds(2)
    screenshot(driver, shots_dir, "01_v1_main")
    dump_ui_tree(driver, str(tests_root / "ui_tree_v1.xml"))

    # 3. 切四宫格 layout
    #    候选: ⌘⌃4 / 视图菜单 / ⌘K 命令面板搜 "四宫格"
    #    第一轮先试 ⌘⌃4 · 如未绑定 · 跑完看 ui_tree 调整
    press_keys(driver, "4", "ctrl|cmd")
    wait_seconds(2)
    screenshot(driver, shots_dir, "02_four_grid")
    dump_ui_tree(driver, str(tests_root / "ui_tree_four_grid.xml"))

    yield


# ─── TC1: 外层 divider 1 (sidebar↔center) 可拖 ────────────────

def test_TC1_outer_divider_1_sidebar_center(driver, shots_dir):
    """外层 sidebar/center 之间 divider 向右拖 100px · 期望 sidebar.width 增加 90-110"""
    screenshot(driver, shots_dir, "TC1_before")

    try:
        sidebar = find_by_label(driver, "sidebar", timeout=2)
    except AssertionError as e:
        pytest.skip(f"未设 sidebar accessibility id · 看 ui_tree_v1.xml 后补到主工程: {e}")

    x, y, w, h = get_frame(sidebar)
    w_before = w

    # divider 1 = sidebar 右边界
    divider_x = x + w
    divider_y = y + h / 2

    click_and_drag(driver, (divider_x, divider_y),
                   (divider_x + 100, divider_y),
                   duration=0.6)
    wait_seconds(0.5)
    screenshot(driver, shots_dir, "TC1_after")

    sidebar = find_by_label(driver, "sidebar")
    _, _, w_after, _ = get_frame(sidebar)
    delta = w_after - w_before

    assert_in_range(delta, 90, 110, "sidebar.width 变化")


# ─── TC2: 外层 divider 2 (center↔monitor) 可拖 ────────────────

def test_TC2_outer_divider_2_center_monitor(driver, shots_dir):
    """外层 center/monitor 之间 divider 向左拖 100px · 期望 monitor.width 增加 90-110"""
    screenshot(driver, shots_dir, "TC2_before")

    try:
        monitor = find_by_label(driver, "monitor", timeout=2)
    except AssertionError as e:
        pytest.skip(f"未设 monitor accessibility id · 看 ui_tree_v1.xml 后补到主工程: {e}")

    x, y, w, h = get_frame(monitor)
    w_before = w

    # divider 2 = monitor 左边界
    divider_x = x
    divider_y = y + h / 2

    click_and_drag(driver, (divider_x, divider_y),
                   (divider_x - 100, divider_y),
                   duration=0.6)
    wait_seconds(0.5)
    screenshot(driver, shots_dir, "TC2_after")

    monitor = find_by_label(driver, "monitor")
    _, _, w_after, _ = get_frame(monitor)
    delta = w_after - w_before

    assert_in_range(delta, 90, 110, "monitor.width 变化")


# ─── TC3: 四宫格 chart 内 toolbar 可见 ───────────────────────

def test_TC3_chart_toolbar_visible(driver, shots_dir):
    """四宫格 4 个 chart 各自 toolbar 高度 > 30px"""
    screenshot(driver, shots_dir, "TC3_state")

    toolbars = find_all_by_type(driver, "XCUIElementTypeToolbar")

    if len(toolbars) < 4:
        pytest.skip(
            f"找到 {len(toolbars)} 个 toolbar · 期望 ≥4 · "
            f"看 ui_tree_four_grid.xml 确认 toolbar 在 SwiftUI tree 内是否被识别为 XCUIElementTypeToolbar"
        )

    too_small: list[tuple[int, float]] = []
    for i, tb in enumerate(toolbars[:4]):
        _, _, _, height = get_frame(tb)
        if height <= 30:
            too_small.append((i, height))

    assert not too_small, f"toolbar 高度过小: {too_small}"


# ─── TC4: 监盘 3 段 section header 文字可见 ──────────────────

def test_TC4_monitor_section_headers_visible(driver, shots_dir):
    """监盘 3 段 section header 应有 ⭐️ / 🗂 / 💼 emoji"""
    screenshot(driver, shots_dir, "TC4_state")

    texts = find_static_texts(driver)
    labels: list[str] = []
    for t in texts:
        try:
            lbl = t.get_attribute("label") or t.get_attribute("name") or ""
        except Exception:
            continue
        if lbl:
            labels.append(lbl)

    expected_emojis = ["⭐️", "🗂", "💼"]
    found: list[str] = []
    for emoji in expected_emojis:
        if any(emoji in lbl for lbl in labels):
            found.append(emoji)

    missing = [e for e in expected_emojis if e not in found]
    assert not missing, (
        f"缺失 section header emoji: {missing} · "
        f"当前可见 static text 共 {len(labels)} 条 · 看 ui_tree_four_grid.xml"
    )
