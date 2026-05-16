"""通用 Appium Mac2 操作 helpers

所有 generated/*.py 都 import 这里的函数 · 避免重复样板。
"""
from __future__ import annotations

import os
import time
from typing import Optional, Tuple


def screenshot(driver, shots_dir: str, name: str) -> str:
    """截图 → shots_dir/<name>.png · 返回绝对路径"""
    path = os.path.join(shots_dir, f"{name}.png")
    driver.save_screenshot(path)
    return path


def press_keys(driver, key: str, modifiers: Optional[str] = None) -> None:
    """按键 · key='1' modifiers='ctrl|cmd' 表示 ⌃⌘1

    modifiers 可选: "cmd" "ctrl" "alt" "shift" 或它们用 | 拼起来
    """
    entry: dict = {"key": key}
    if modifiers:
        entry["modifierFlags"] = modifiers
    driver.execute_script("macos: keys", {"keys": [entry]})


def type_text(driver, text: str) -> None:
    """连续输入字符串"""
    driver.execute_script("macos: keys", {"keys": [{"text": text}]})


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


def dump_ui_tree(driver, out_path: str) -> str:
    """dump 当前 UI accessibility tree (XML) · 调试时让 Claude 看树"""
    xml = driver.page_source
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(xml)
    return out_path


def wait_seconds(seconds: float) -> None:
    """显式等待 · 用于 layout 稳定 / 动画完成"""
    time.sleep(seconds)
