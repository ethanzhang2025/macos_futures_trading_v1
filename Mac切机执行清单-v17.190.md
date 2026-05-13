# Mac 端执行清单 · v17.190 切机闭环

**目标**：累积 ~434 commit · Mac 首次编译已过（35666b7）· 接 swift test + 增量截图 + 4 项手动验 = 完成切机闭环。

**Mac 环境**：macOS 26.4 / Xcode 26 / swift 6.3.2
**主目录**：`/Users/admin/Documents/MAC版本_期货交易终端/macos_futures_trading_v1`
**独立 build path**：`/tmp/build_v1730_b1`

---

## 0 · 拉最新（含本次脚本 bug 修复）

```bash
cd /Users/admin/Documents/MAC版本_期货交易终端/macos_futures_trading_v1
git status                      # 应 clean（如有本地改动先告诉我）
git pull --ff-only origin main  # 拉本次 commit（脚本 bug 修复）
git log --oneline -5            # 确认最新 commit
```

**期望**：HEAD 在 v17.191（脚本 bug 修复）或更新 · `mac_acceptance_v17_170_189.sh` 和 `.applescript` 都已更新。

---

## 1 · swift test（期 2965 全绿 · 与 Linux 一致）

```bash
swift test --build-path /tmp/build_v1730_b1 2>&1 | tee ~/Desktop/v17190_mac_test.log
# 看尾巴
tail -20 ~/Desktop/v17190_mac_test.log
```

**期望最后一行**：`Test Suite 'All tests' passed at ... · Executed 2965 tests`

**如果失败**：
```bash
# scp 完整 log 回 Linux 给我看
scp ~/Desktop/v17190_mac_test.log beelink@vvsvr:/tmp/v17190_mac_test.log
```
然后告诉我："Mac 测试失败 · log 已传 /tmp/v17190_mac_test.log"

---

## 2 · 增量截图 5 张（v17.170-189 主图 overlay 自动验）

**前提**：步骤 1 测试通过 · 否则跳过这步先修测试。

```bash
chmod +x mac_acceptance_v17_170_189.sh
./mac_acceptance_v17_170_189.sh
```

**脚本会做什么**（已修 bug · 主程序起不来不截图）：
1. nohup swift run MainApp
2. **轮询等 ≤180s 让主进程出现**（首次编译慢也兜得住）
3. **轮询等 ≤30s 让主窗口出现**
4. 额外 3s 缓冲让 Sina 首拉 + 主图渲染
5. 二次确认进程仍在跑（防 crash 后截桌面）
6. 调 applescript：⌘N → ⌘⇧P → ⌘⇧L → ⌘⇧Y → ⌘⌥⇧Y → ⌘⌥G 顺序触发 + 5 张截图
7. 自动 scp 到 `beelink@vvsvr:/tmp/mac_acceptance_v17_170_189/`

**5 张截图清单**：
| # | 文件 | 验证 |
|---|---|---|
| 24 | `24_v17188_patterns_overlay.png` | ⌘⇧P PatternDetector v4 形态识别 overlay（13 种形态） |
| 25 | `25_v17182_patterns_list_sheet.png` | ⌘⇧L 形态清单 sheet（含 stats 区） |
| 26 | `26_v17180_resonance_overlay_hud.png` | ⌘⇧Y 多周期共振 overlay + 左上 HUD |
| 27 | `27_v17184_resonance_stats_sheet.png` | ⌘⌥⇧Y 共振历史回测 sheet |
| 28 | `28_v17189_secondary_picker_sheet.png` | ⌘⌥G 多合约 overlay picker（本 session 主功能） |

**失败诊断**（脚本会自动 exit 2/3/4 + tail app log）：
- exit 2 = 主进程 180s 未出现 → 多半 swift build 失败 · 看 `~/Desktop/mac_acceptance_v17_170_189/app_stdout.log`
- exit 3 = 主窗口 30s 未出现 → app 起来但 SwiftUI 没 render · 看 stdout log
- exit 4 = 进程窗口出现后又消失 → app crash · 看 stdout log

跑完后告诉我："增量截图完成 · N=X/5"，我从 vvsvr 上拉看图。

---

## 3 · 4 项手动验（每项 1-2 min · 完成后告诉我哪几项过）

**前提**：步骤 2 自动截图过了 · app 还在运行（或者重新 `swift run MainApp`）。

### 3.1 ⌘⌥L 跨合约联动窗口
- 操作：在主图按 ⌘⌥L
- 期望：弹出独立窗口 · 显示当前合约的关联品种（CrossLinkageEngine 推荐 · 如 IF→IH/IC、SR→CF）· 点击合约能跳转

### 3.2 盘中复盘 calendar 按钮
- 操作：主图 toolbar 找日历图标 · 或菜单 View → 盘中复盘
- 期望：弹出 calendar 选日期 · 选完后载入当日 1m bar · 进度条 / 播放控制可用

### 3.3 主图右键 OHLC + 形态 Markdown
- 操作：在主图 K 线上右键
- 期望：context menu 出现 "复制 OHLC（Markdown）" / "复制形态（Markdown）"（v17.187 OHLCMarkdownExporter v2）· 复制到剪贴板后用 Notes 粘贴看格式

### 3.4 CSV 导入 ⌘⇧⌥I
- 操作：按 ⌘⇧⌥I（macOS 全局）
- 期望：弹出文件选择 sheet · 选 CSV → 解析进度条 → 完成 toast · 可在主图选导入的合约

**结果上报模板**（粘贴到聊天）：
```
4 项手动验结果：
- 3.1 ⌘⌥L 跨合约：✅ / ❌（如失败简述现象）
- 3.2 盘中复盘 calendar：✅ / ❌
- 3.3 右键 OHLC + 形态 MD：✅ / ❌
- 3.4 CSV 导入 ⌘⇧⌥I：✅ / ❌
```

---

## 4 · 闭环判定

| 步骤 | 通过条件 | 失败处理 |
|---|---|---|
| 1 swift test | 2965 全绿 | scp log 回 Linux · 我远程修 |
| 2 增量截图 | 5/5 全有图 · 内容对 | 看 app_stdout.log · 我远程修 |
| 3.1-3.4 手动验 | 4/4 过 | 单项失败我远程修对应模块 |

**全过 → v17.190 切机闭环正式完成**。
继续 🥈 simplifier 批量复审 v17.180-189。

---

## 5 · 速查命令

```bash
# 仅编译（跳过 test/截图 · 先验编译还过）
swift build --build-path /tmp/build_v1730_b1

# 仅单功能单测
swift test --build-path /tmp/build_v1730_b1 --filter "MultiInstrumentNormalizerTests"   # 12
swift test --build-path /tmp/build_v1730_b1 --filter "PatternDetectorTests"             # 31

# 手动启动 app（绕开 acceptance 脚本）
swift run MainApp --build-path /tmp/build_v1730_b1

# 清独立 build cache（万一异常）
rm -rf /tmp/build_v1730_b1
```

---

## 6 · 关键提醒

- 步骤 1 测试必须先过 · 测试不过截图无意义
- 截图脚本已修 bug：主程序起不来 / 窗口没出来 / app crash → 直接 exit 不截桌面
- 4 项手动验是 v17.165-185 的非快捷键交互 · 必须人工触发
- 任何步骤卡住超过 5 分钟 → 截 terminal 图发我，我远程诊断
