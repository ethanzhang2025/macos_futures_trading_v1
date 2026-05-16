# Appium Mac2 UI 测试闭环

Linux 端 Claude 改代码 → Mac 端 1 行命令 → 结果自动回传 Linux → Claude 修复 · 循环。

---

## 整体流程

```
[Linux] Claude 改 Sources/MainApp/...
        push origin appkit-shell-rewrite
                  ↓
[Mac]   cd <repo>
        git pull --ff-only && ./mac_loop.sh   ← 你唯一做的事
                  ↓
        mac_loop.sh 8 步全自动:
          1. 环境自检 + venv setup
          2. (用户已 pull · 不重复)
          3. ./run-mac.sh debug build → MainApp.app
          4. 后台启 appium server (port 4723)
          5. pytest ui_tests/generated/ --json-report
          6. 收集 result.json / shots/ / logs
          7. scp → vvsvr:/home/beelink/debug_img/appium_loop_latest/
          8. cleanup
                  ↓
[Linux] Claude: ./pull_results.sh
        读 result.json + 看 shots/*.png + 读 ui_tree_*.xml
        锁定 root cause → 改代码 → 循环
```

---

## 一次性安装（5-10 分钟 · 永远只做一次）

```bash
# 1. 系统级工具（brew · 没有 PEP 668 限制）
brew install node python@3.11

# 2. Appium 全局 + Mac2 driver
npm install -g appium
appium driver install mac2

# 3. macOS 系统设置 · 必须 GUI 手动（脚本无法）
# 系统设置 → 隐私与安全 →
#   · 辅助功能           → + Terminal (或 iTerm)
#   · 屏幕录制 与 系统录音 → + Terminal
#   · 自动化             → Terminal → 系统事件 ✓
```

**验证**：
```bash
node -v && python3 -V && appium driver list --installed | grep mac2
```
看到三个版本号 + `✓ mac2@x.x.x` 即 OK。

> Python venv / pip 依赖 · npm 全局 driver · 都不需要手动管。首次 `./mac_loop.sh` 会自动建 `ui_tests/.venv/` + `pip install -r requirements.txt`。

---

## 每次跑（两行命令）

```bash
cd /Users/admin/Documents/MAC版本_期货交易终端/macos_futures_trading_v1
git pull --ff-only && ./mac_loop.sh
```

看到 `✅ mac_loop done` 即可。告诉 Claude「跑完了」。

---

## 目录结构

```
ui_tests/
├── specs/                  ← 用户写 Markdown 测试说明（人 + AI 共读）
│   └── 5.1_四宫格divider拖动.md
├── generated/              ← Claude 从 specs/ 翻译的 pytest .py（autogen · 改 specs 后重生成）
│   └── test_5_1_four_grid_divider.py
├── conftest.py             ← pytest fixture · appium driver 启停（必须在 ui_tests/ 根 · pytest 自动加载）
├── lib/
│   └── helpers.py          ← clickAndDrag / pressKeys / find_by_label / dump_ui_tree
├── shots/                  ← runtime 截图（gitignore）
├── result.json             ← pytest --json-report 输出
├── pytest.log
├── ui_tree_*.xml           ← appium dump 的 UI accessibility tree（调试用）
├── requirements.txt        ← Python deps
├── .venv/                  ← Python venv（gitignore · 脚本自动建）
└── README.md
```

---

## 加新测试场景的工作流

1. **你**：在 `ui_tests/specs/` 写新 .md（按 `5.1_四宫格divider拖动.md` 的结构）
2. **你**：告 Claude「生成 specs/xxx.md 对应的测试」
3. **Claude**：在 `ui_tests/generated/` 写对应 .py + commit + push
4. **你**：`git pull && ./mac_loop.sh`
5. **Claude**：拉 result.json 看 pass/fail · 改主工程 → 循环

---

## 第一次跑可能 skip 大半 · 这是正常的

主工程 SwiftUI view 多数没设 `.accessibilityIdentifier("xxx")` · appium 找不到元素时 pytest 会 `skip` 而不是 `fail`。

第一轮的关键产出：
- `ui_tests/ui_tree_v1.xml`（appium dump 整个窗口 UI tree）
- `ui_tests/shots/00_v1_main.png`（V1 主窗截图）

Claude 据此：
1. 看 ui_tree_v1.xml · 找到 sidebar / center / monitor 等元素在 tree 里的位置 + 当前 label
2. 给 `Sources/MainApp/AppKitShell/MainSplitViewController.swift` 等加 `.accessibilityIdentifier("sidebar")`
3. push · 你再跑一次 · skip 应该转 pass

---

## 故障排查

| 症状 | 解决 |
|---|---|
| `appium 启动超时` | 看 `/tmp/appium_*.log` · 通常端口 4723 被占（`lsof -i :4723`）或 mac2 driver 损坏（重装：`appium driver uninstall mac2 && appium driver install mac2`） |
| `.app 闪退` | 看 RESULTS 内 `app_stdout.log` · 通常是 swift build 问题 |
| `找不到元素` | 看 `ui_tree_*.xml` 知道当前 tree · 让 Claude 补 accessibility id |
| 权限弹窗反复弹 | 系统设置 → 隐私与安全 重新勾 Terminal（重启 Terminal 后再跑） |
| `scp 失败` | 测试 `ssh beelink@vvsvr` 通否 · key 是否在 `~/.ssh/` |

---

## 设计原则

- **specs/*.md 是唯一真理源** · generated/*.py 是 derived artifact · 改 .md 重新生成 .py 即可
- **用户认知负担 = 0** · 看到 `✅ done` 就告 Claude 一声 · 其他不管
- **第一次失败是常态** · 不是 bug · 是闭环建立过程的必经
- **Mac 端永远只跑测试 · 不存代码改动** · 所有 commit 都在 Linux 端发起
