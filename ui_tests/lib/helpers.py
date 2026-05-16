"""通用 Appium Mac2 操作 helpers

所有 generated/*.py 都 import 这里的函数 · 避免重复样板。

v17.255 修 · modifier 改用 NSEventModifierFlags 整数 · 加 click_menu_item。
之前 modifierFlags="ctrl|cmd" 字符串被 mac2 driver 忽略 · 快捷键不生效。
"""
from __future__ import annotations

import os
import time
from typing import Optional, Tuple, Union

# ─── NSEventModifierFlags raw values（macOS Cocoa 原生）─────────────
# 必须用整数 · mac2 driver 不接受字符串
MOD_CAPS_LOCK = 1 << 16   # 65536
MOD_SHIFT     = 1 << 17   # 131072
MOD_CONTROL   = 1 << 18   # 262144   ← ⌃
MOD_OPTION    = 1 << 19   # 524288   ← ⌥
MOD_COMMAND   = 1 << 20   # 1048576  ← ⌘
MOD_FUNCTION  = 1 << 23

# 常用组合
MOD_CMD       = MOD_COMMAND
MOD_CTRL      = MOD_CONTROL
MOD_ALT       = MOD_OPTION
MOD_CMD_CTRL  = MOD_COMMAND | MOD_CONTROL   # ⌘⌃ (V1 主窗专属前缀)
MOD_CMD_SHIFT = MOD_COMMAND | MOD_SHIFT
MOD_CMD_ALT   = MOD_COMMAND | MOD_OPTION


# ─── 截图 ────────────────────────────────────────────────

def screenshot(driver, shots_dir: str, name: str) -> str:
    """截图 → shots_dir/<name>.png · 返回绝对路径"""
    path = os.path.join(shots_dir, f"{name}.png")
    driver.save_screenshot(path)
    return path


# ─── 键盘 ────────────────────────────────────────────────

def press_keys(driver, key: str, modifiers: Optional[int] = None) -> None:
    """按键 · key='1' modifiers=MOD_CMD_CTRL 表示 ⌃⌘1

    modifiers 必须是 NSEventModifierFlags 整数（用 MOD_xxx 常量 | 组合）
    示例:
        press_keys(driver, "1", MOD_CMD_CTRL)   # ⌃⌘1
        press_keys(driver, "k", MOD_CMD)        # ⌘K
        press_keys(driver, "i", MOD_CMD_CTRL)   # ⌃⌘I
    """
    entry: dict = {"key": key}
    if modifiers is not None:
        entry["modifierFlags"] = int(modifiers)
    driver.execute_script("macos: keys", {"keys": [entry]})


def type_text(driver, text: str) -> None:
    """连续输入字符串"""
    driver.execute_script("macos: keys", {"keys": [{"text": text}]})


# ─── 菜单导航（V1 主窗 / 四宫格 切换走菜单 · 不依赖快捷键）─────────

def _xpath_quote(s: str) -> str:
    """XPath 字符串字面量 quote · 兼容中英文 / emoji"""
    if "'" not in s:
        return f"'{s}'"
    if '"' not in s:
        return f'"{s}"'
    parts = s.split("'")
    return "concat(" + ", \"'\", ".join(f"'{p}'" for p in parts) + ")"


def click_menu_item(driver, *menu_path: str, settle: float = 0.4) -> None:
    """逐级点击 macOS menubar 上的 menu 路径

    用法:
        click_menu_item(driver, "工具", "🆕 主工作台 V1 · AppKit（⌘⌃1）")
        click_menu_item(driver, "视图", "V1 主窗面板布局", "⊞ 四宫格")

    实现:
        第 1 级 = XCUIElementTypeMenuBarItem (顶级 menu)
        第 2+ 级 = XCUIElementTypeMenuItem (子项)
        按 @title 属性匹配（ui_tree dump 看到的 title 字段）
    """
    for i, item_title in enumerate(menu_path):
        quoted = _xpath_quote(item_title)
        if i == 0:
            xpath = f"//XCUIElementTypeMenuBarItem[@title={quoted}]"
        else:
            xpath = f"//XCUIElementTypeMenuItem[@title={quoted}]"
        try:
            el = driver.find_element("xpath", xpath)
        except Exception as e:
            raise AssertionError(
                f"找不到 menu path 第 {i+1} 级: {item_title!r}\n"
                f"  xpath: {xpath}\n"
                f"  错误: {e}"
            )
        el.click()
        time.sleep(settle)


# ─── 鼠标 ────────────────────────────────────────────────

def click_and_drag(driver, from_xy: Tuple[float, float],
                   to_xy: Tuple[float, float],
                   duration: float = 0.5) -> None:
    """鼠标从 (x1,y1) 拖到 (x2,y2)"""
    driver.execute_script("macos: clickAndDrag", {
        "fromX": float(from_xy[0]),
        "fromY": float(from_xy[1]),
        "toX": float(to_xy[0]),
        "toY": float(to_xy[1]),
        "duration": float(duration),
    })


def click_at(driver, xy: Tuple[float, float]) -> None:
    """鼠标点击 (x, y)"""
    driver.execute_script("macos: click", {
        "x": float(xy[0]),
        "y": float(xy[1]),
    })


# ─── 元素查询 ────────────────────────────────────────────

def find_by_label(driver, label: str, timeout: float = 5):
    """按 accessibility identifier 找元素 · 找不到 raise AssertionError"""
    end = time.time() + timeout
    last_exc = None
    while time.time() < end:
        try:
            return driver.find_element("accessibility id", label)
        except Exception as e:
            last_exc = e
            time.sleep(0.25)
    raise AssertionError(f"未找到 accessibility id = {label!r} · 最后异常: {last_exc}")


def find_all_by_type(driver, xcui_type: str) -> list:
    """按 XCUI 类型找所有元素 · e.g. 'XCUIElementTypeToolbar'"""
    try:
        return driver.find_elements("class name", xcui_type)
    except Exception:
        return []


def find_static_texts(driver) -> list:
    """所有静态文本元素"""
    return find_all_by_type(driver, "XCUIElementTypeStaticText")


def find_window_by_id(driver, window_identifier_substring: str, timeout: float = 5):
    """等待并返回 identifier 包含指定子串的 NSWindow"""
    end = time.time() + timeout
    while time.time() < end:
        try:
            windows = driver.find_elements("class name", "XCUIElementTypeWindow")
            for w in windows:
                try:
                    ident = w.get_attribute("identifier") or ""
                except Exception:
                    ident = ""
                if window_identifier_substring in ident:
                    return w
        except Exception:
            pass
        time.sleep(0.4)
    raise AssertionError(
        f"未找到 identifier 包含 {window_identifier_substring!r} 的窗口 · {timeout}s 超时"
    )


# ─── 几何 / 断言 ────────────────────────────────────────

def get_frame(element) -> Tuple[float, float, float, float]:
    """返回元素 (x, y, w, h)"""
    loc = element.location
    size = element.size
    return (
        float(loc["x"]), float(loc["y"]),
        float(size["width"]), float(size["height"]),
    )


def assert_in_range(actual: float, low: float, high: float, name: str = "value") -> None:
    assert low <= actual <= high, \
        f"{name} = {actual} 不在 [{low}, {high}] 区间"


# ─── 调试 ────────────────────────────────────────────────

def dump_ui_tree(driver, out_path: str) -> str:
    """dump 当前 UI accessibility tree (XML) · 调试时让 Claude 看树"""
    xml = driver.page_source
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(xml)
    return out_path


def wait_seconds(seconds: float) -> None:
    """显式等待 · 用于 layout 稳定 / 动画完成"""
    time.sleep(seconds)
