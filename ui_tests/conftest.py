"""pytest fixtures · Appium Mac2 driver 启停 + 项目级配置

环境变量 (由 mac_loop.sh 注入):
- APP_PATH    : MainApp.app 绝对路径
- APPIUM_URL  : http://127.0.0.1:4723/wd/hub
"""
from __future__ import annotations

import os
import sys
import time
from pathlib import Path

import pytest

# conftest.py 在 ui_tests/ 根 · helpers.py 在 ui_tests/lib/
# 把 lib/ 加进 sys.path · generated/*.py 可 from helpers import ...
_LIB_DIR = Path(__file__).resolve().parent / "lib"
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))


def _resolve_app_path() -> str:
    p = os.environ.get("APP_PATH")
    if p and Path(p).exists():
        return p
    # 兜底: 从仓库根推算（conftest 在 ui_tests/ 根 · 仓库根 = parents[1]）
    repo_root = Path(__file__).resolve().parents[1]
    candidate = repo_root / ".build" / "debug" / "MainApp.app"
    if candidate.exists():
        return str(candidate)
    raise RuntimeError(
        f"找不到 MainApp.app · 请先 ./run-mac.sh debug build · 或设 APP_PATH 环境变量"
    )


def _resolve_appium_url() -> str:
    return os.environ.get("APPIUM_URL", "http://127.0.0.1:4723/wd/hub")


@pytest.fixture(scope="session")
def app_path() -> str:
    return _resolve_app_path()


@pytest.fixture(scope="session")
def shots_dir() -> str:
    p = Path(__file__).resolve().parent / "shots"
    p.mkdir(parents=True, exist_ok=True)
    return str(p)


@pytest.fixture(scope="session")
def driver(app_path):
    """Session 级 driver · 整组测试共享一个 .app 实例"""
    from appium import webdriver
    from appium.options.mac import Mac2Options

    options = Mac2Options()
    options.app = app_path
    options.bundle_id = "com.futuresterminal.macos"
    options.new_command_timeout = 300
    options.show_server_logs = False

    print(f"\n[driver] connecting appium @ {_resolve_appium_url()}")
    print(f"[driver] app: {app_path}")
    drv = webdriver.Remote(_resolve_appium_url(), options=options)
    drv.implicitly_wait(3)

    # 主程序冷启动需要等 Sina 首次拉数据等 · 给 5s
    time.sleep(5)

    yield drv

    try:
        drv.quit()
    except Exception:
        pass
