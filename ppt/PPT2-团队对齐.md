---
marp: true
theme: default
paginate: true
size: 16:9
backgroundColor: '#FAFAFA'
color: '#1A1A1A'
style: |
  section {
    font-family: 'PingFang SC', 'SF Pro Display', -apple-system, BlinkMacSystemFont, sans-serif;
    padding: 50px 70px;
    font-size: 22px;
    line-height: 1.6;
  }
  h1 {
    color: #1A1A1A;
    font-size: 48px;
    font-weight: 700;
    letter-spacing: -0.5px;
  }
  h2 {
    color: #2563EB;
    font-size: 32px;
    font-weight: 600;
    border-bottom: 3px solid #2563EB;
    padding-bottom: 8px;
    margin-top: 0;
  }
  h3 {
    color: #1A1A1A;
    font-size: 24px;
    font-weight: 600;
  }
  strong {
    color: #2563EB;
  }
  em {
    color: #666666;
    font-style: normal;
  }
  blockquote {
    border-left: 4px solid #2563EB;
    padding: 10px 20px;
    color: #444;
    font-style: normal;
    background: #F3F4F6;
  }
  table {
    font-size: 18px;
    border-collapse: collapse;
    margin: 15px auto;
  }
  th {
    background: #2563EB;
    color: white;
    padding: 8px 12px;
    text-align: left;
    font-weight: 600;
  }
  td {
    padding: 8px 12px;
    border-bottom: 1px solid #E5E7EB;
  }
  code {
    font-family: 'JetBrains Mono', 'SF Mono', Consolas, monospace;
    background: #F0F4F8;
    padding: 2px 6px;
    border-radius: 4px;
    font-size: 0.9em;
  }
  section.cover {
    background: #1A1A1A;
    color: #FAFAFA;
    padding: 80px;
  }
  section.cover h1 {
    color: #FAFAFA;
    font-size: 58px;
    border: none;
  }
  section.cover h2 {
    color: #9CA3AF;
    border: none;
    font-size: 28px;
  }
  section.accent {
    background: #2563EB;
    color: white;
  }
  section.accent h1, section.accent h2 {
    color: white;
    border: none;
  }
  .muted {
    color: #666666;
  }
  ul li, ol li {
    margin-bottom: 6px;
  }
---

<!-- _class: cover -->

# 团队对齐 · 全览

## 中国期货 Mac/iPad 原生交易终端

合伙人 & 招聘对齐用

*v1 · 2026-04-23*

---

## 为什么做这件事

**市场缺口清晰可见**：

- 中国期货主流终端（文华 / 博易 / 快期 / 易盛）全部 **Windows MFC/Delphi 老架构**
- UI / 性能 / 跨端体验 **严重落后于时代 10+ 年**
- Mac 期货用户 **≈ 20 万**，但没有合适工具 → 被迫 Parallels 或将就

**时代窗口**：Apple Silicon + SwiftUI + iPad Pro 打开了真实机会

**选择的本质**：做一款我们自己作为交易者会用的工具

---

## Vision & Mission

**Vision · 愿景**
> 中国期货版的 **TradingView × Linear × iPad Pro** 专业工作流
> 最好看、最快、最克制的 Mac/iPad 原生期货终端

**Mission · 使命**
> **"让 Mac 用户在中国期货市场，拥有一款超一流的原生交易工具。"**

用于：官网 About / 融资 Deck / 招聘页 / 对外采访

---

## 项目画像 · 我们怎么做

**三个关键约束**：

| 项 | 现状 |
|----|------|
| 启动资金 | **¥20 万** |
| 团队 | **2 人全职 + 兼职顾问** |
| 跑道 | **6-9 月** |
| 冷启动基础 | 期货圈种子用户 **2 人** |
| Plan B | **硬扛到底**（配死亡率自检预警）|

**决策底色**：没有烧钱打磨 18 月的奢侈 · 必须以战养战

---

## 战略路径 · 以战养战两阶段

```
M0 ───────── M9 ── M12 ───────── M24 ──────────> M36+
    Stage A         Stage B                Stage C
    活下来          做大                   扩张 or 退出
    ¥20w ARR        ¥2000w ARR             据结果定
```

- **Stage A**（M0-M9）· 图表+复盘工具，不接 CTP，**活下来**
- **Stage B**（M12-M24）· CTP 下单 + 麦语言完整兼容 + iPad 专业，**做大**
- **Stage C**（M24+）· Windows / 证券 / 出海 / 策略市场（据结果定）

---

## 4 个核心假设 × 验证节点

| # | 假设 | 验证节点 | 验证失败 → |
|---|------|---------|----------|
| 1 | Mac 用户对品质付费意愿强 | M6 首批付费 | 核心前提破产，重启 |
| 2 | 销售合伙人 Hunter 模式可持续 | M3 TestFlight 周新增 ≥ 20 | 改渠道或 Plan B |
| 3 | 麦语言兼容是文华迁移关键 | Stage A 晚期 P3 转化率 | 放弃迁移战略 |
| 4 | 券商代付商业模式成立 | Stage B 中段首家券商签约 | 转纯 B2C |

---

## 市场 · TAM / SAM / SOM

```
中国期货活跃账户数（2024 估）≈ 250 万
├─ Mac 用户渗透率 ≈ 8%          → Mac 期货用户 ≈ 20 万
├─ 其中专业付费意愿 ≈ 30%       → Pro 级 Mac 用户 ≈ 6 万
└─ 按 ¥399/年定价              → TAM = ¥2400 万/年
```

- **SAM**（10 年 30% 渗透）：**¥720 万 ARR**
- **SOM 分阶段**：M9 ¥20 万 → M18 ¥200 万 → M24 ¥2000 万+

**最坏情况**：Mac 渗透 5% + 付费意愿 15% → TAM ¥750 万 · 仍支撑千万级生意

---

## 竞争格局

| 竞品 | 市占 | 年价 | Mac | 麦语言 | 审美 |
|------|:---:|:---:|:---:|:---:|:---:|
| 文华赢顺 | 70-80% | ¥798-1880 | ❌ | ✅✅ | ★ |
| 博易大师 | 10-15% | 券商免费 | ❌ | 部分 | ★ |
| 快期 V4 | 5-10% | 免费 | ⚠️ | ❌ | ★★ |
| 易盛极星 | < 5% | 券商绑 | ❌ | ❌ | ★ |
| **我们** | 目标 1-3% | **¥399** | **原生** | **95%+** | **★★★★★** |

**关键**：文华 ¥1880 已教育出"年付千元"预算认知 → 我们 ¥399 让深度用户"不假思索下单"

---

## Persona · 4 层人群（Stage A 聚焦 P1/P2）

| # | Persona | Stage A | Stage B | 规模 |
|---|---------|:------:|:------:|:---:|
| **P1** | Mac 主观 Pro 交易者（全职/认真兼职）| **65%** | 50% | 3-5 万 |
| **P2** | Mac 半职业波段（白领/自由职业）| **25%** | 20% | 10-15 万 |
| **P3** | 文华迁移者（麦语言锁定）| 10% | **20%** | 5-10 万 |
| **P4** | 技术型主观交易者 | ~0% | 10% | 2-5 万 |

**Stage A 主战场**：P1（Mac + 全职 + 审美觉醒）
**Stage B 增量**：P3（麦语言解锁后的文华迁移潮）

---

## 产品全景 · Stage A/B/C 矩阵

| 维度 | Stage A | Stage B | Stage C |
|------|---------|---------|---------|
| 图表 | Metal 60fps | + 多屏 | — |
| 指标 | **56 → 80** | + 100 | + 用户贡献 |
| 画线 | 6 | + Apple Pencil | — |
| 复盘 | 8 张图 | + 高级 | — |
| **K 线回放** | **✓** | + 联动 | — |
| **条件预警** | **✓** | + 推送 | — |
| **交易日志** | **✓** | + AI 分析 | — |
| **模拟训练** | **✓** | + 场景回放 | — |
| **工作区模板** | **✓** | + 团队共享 | — |
| 下单 | ❌ | **CTP 全套** | + 多柜台 |
| 麦语言 | 基础 30-50 | **95%+ 完整** | — |
| iPad | 基础 | **6 大独家场景** | — |

---

## 12 核心模块 · Stage A 做什么

**图表与指标（4 个）**
1. **Metal 自研图表引擎**（核心差异化，10 万 K 线 60fps）
2. **指标库 56 个 v1**（含期货特有 12 个 TradingView 没有）
3. **画线工具 6 种**
4. **复盘分析 8 张图**（品种热力矩阵 + 时段分析 = 差异化）

**工作流 5 个**（Stage A 新增 · ChatGPT 洞察补全）
5. **K 线回放** · 沉浸式复盘
6. **条件预警中心** · 专业刚需
7. **交易日志** · 最高粘性（日积月累无法迁移）
8. **模拟训练** · 接 SimNow 无接入成本
9. **工作区模板** · 多布局一键切换

**战略储备（3 个）**
10. **CTP 下单**（Stage B 核心）
11. **麦语言解析器**（战略武器 · Stage A 晚期基础版启动）
12. **iPad 专业工作流**（Stage B 独家，Apple 生态护城河）

---

## 差异化 6 维 + 不做清单

**差异化 6 维（必须同时成立）**：
1. 审美与性能（Metal 60fps）
2. Mac 原生
3. Apple 生态整合
4. Mac+iPad+iPhone 协同
5. 透明定价 + 不卖数据
6. **麦语言完整兼容**

**不做清单（DNA 红线）**：
Windows 版 ❌ 自营/沉淀资金 ❌ 投资建议 ❌ 社区/自媒体 ❌ 散户低价版 ❌ 数据倒卖 ❌

---

## 产品原则 7 条（决策裁决书）

1. **Ship weekly, polish later** · 每周必发
2. **Charge early, be transparent** · 能收费就早收费
3. **Fast is a feature** · 一切 < 100ms
4. **Mac-native aesthetic, not Mac-only lock-in** · UI 原生但逻辑跨平台
5. **Keyboard is first-class** · 全键盘可达
6. **Multi-device is multi-context** · iPad/iPhone 不是 Mac 缩放
7. **Respect traders' money and attention** · 稳定 > 创新

**冲突优先级**：**7 > 3 > 2 > 1 > 其他**（稳定 > 速度 > 现金 > 节奏）

---

## 北极星 · WAPU

**Weekly Active Pro Users** · 过去 7 天内至少打开 3 次的 Pro 订阅用户数

**为什么**：一个数字 = 付费（商业价值）× 活跃（用户价值） · 过滤僵尸付费

| Stage | 北极星 | 辅助（领先）| 辅助（滞后）|
|-------|-------|-----------|-----------|
| A | WAPU | TestFlight 周新增 | M1 留存 > 70% |
| B | WAPU | 多端活跃占比 | NRR > 110% |
| C | WAPU | 新市场渗透 | LTV/CAC > 3 |

**每天 9am 开盘前看昨天 WAPU · 连续 7 天持平或下降 → 启动死亡率自检会议**

---

## 商业模式 · B2C 主 + B2B2C 代付辅

**主轴 · B2C 订阅**（60-70%）
- Pro ¥399/年 → Pro Max ¥999/年
- 现金流快 · 品牌资产归自己

**辅轴 · B2B2C 代付**（30-40%，Stage B 启动）· **买单方 4 类**
- 期货公司总部（决策 6-12 月，单价高）
- **营业部（决策 1-3 月，KPI 驱动，优先谈）**
- 大客户团队（服务 HNW，单客户价值最高）
- 高净值客户服务体系（文华/快期没精细化的缝隙）

**统一原则**：产品不分化 · 按人按月结算 · 账户归属仍在我们

**不做**：广告 ❌ 数据倒卖 ❌ 独家席位费 ❌ 一次性买断 ❌

---

## GTM · AARRR 漏斗（Stage A M9 目标）

```
触达     →  TestFlight  →  Pro 付费  →  M1 留存  →  推荐
~1500    ~800 人         ~500 人       > 70%     每月 +10%
         53% 转化         63% 转化
```

**主战场**：合伙人 1v1 Hunter（每天 10-20 条私信 · 每周 30+ 深度对话）

**副战场**：
- 少数派深度投稿（2 篇）
- 即刻 / V2EX 开发日志（你，1 篇/月）
- Mac App Store ASO

**综合 Stage A CAC ≈ ¥0**（无付费推广）

---

## 财务 · 3 年 P&L 骨架

| 年 | 阶段 | 保守 ARR | 乐观 ARR | 净利（保守）|
|----|-----|---------|---------|----------|
| Y1 | Stage A | ¥30 万 | ¥50 万 | **-¥6 万** |
| Y2 | Stage B 早 | ¥200 万 | ¥500 万 | **+¥20 万** |
| Y3 | Stage B 晚 | ¥800 万 | ¥2500 万 | **+¥320 万** |

**单位经济**：CAC < ¥200 · LTV > ¥1500 · **LTV/CAC > 7.5** · 毛利 > 85%

**盈亏平衡**：M11-M12（累计 Pro ~900 人时）

---

## 股权与投资规划

**启动股权（建议）**：

| 持有人 | 比例 |
|-------|:---:|
| 你（CEO）| **55-60%** |
| 合伙人（COO）| **25-30%** |
| 期权池 | **10-15%** |
| 兼职顾问 | **0.5-2%** |

**M1 必签文件**：股东协议 · Vesting（4 年 + 1 年 cliff）· 竞业 · 回购

**3 轮融资后你仍 38%**（> 1/3 重大事项否决权线）

---

## 合规路径（四级）

| 级别 | 时机 | 关键动作 |
|------|------|---------|
| 第一级 | M1 | 公司注册 + 软著 + 律师咨询 |
| 第二级 | M5-M6 | 个保法 + 用户协议 + App Store 审核 |
| 第三级 | Stage B 前 | 适当性管理 + 审计日志 + **E&O 保险** |
| 第四级 | Stage B 后 | 反洗钱 + 中期协备案 |

**红线**：自营 ❌ 沉淀资金 ❌ 投顾 ❌ 配资 ❌ 荐股 ❌ 数据倒卖 ❌

**商标**：中英文 × 类别 9+42+36 × 海外 4 地 = ¥5-8 万（M1-M3 完成）

---

## 组织与招聘 · 按里程碑触发

| 里程碑 | 触发招聘 | 月薪 | 期权 |
|-------|--------|-----|-----|
| M12 Stage B 启动 | iOS/iPad 工程师 + 设计师 | ¥25-50k | 0.2-0.8% |
| M13 | 后端工程师 | ¥25-40k | 0.2-0.5% |
| M14 | 客服/运营 | ¥10-20k | 0.1-0.3% |
| M16 | 图表/麦语言高工 | ¥40-60k | 0.5-1% |
| M18 | BD（券商对接）| ¥20-40k + 提成 | 0.2-0.5% |
| M20+ | PM / QA | ¥20-50k | 0.2-0.8% |

**Stage A 创始人薪酬 ¥8-10k/月 · Stage B 启动后提升至 ¥20-30k**

---

## 客户成功 · 分层 SLA

| 用户等级 | 响应 SLA | 渠道 | 负责人 |
|---------|---------|------|-------|
| Free | 72h | App 内 + FAQ | 自助 |
| Pro | 24h | 邮件 + App 内 | 合伙人 |
| **Pro Max** | **4h** | VIP 微信群 | 合伙人 + 你 |
| 券商代付 | **2h** | 专属经理 | 合伙人 |

**Pro Max VIP 微信群**（≤ 200 人 · 合伙人 9am-9pm 在线）
**NPS 目标**：Stage A > 40 · Stage B > 50

---

## 风险与 Plan B 底线

**最小死亡率自检**：2 指标 + 月度 15 分钟 standup

| 指标 | M6 红线 | M9 红线 |
|------|--------|--------|
| TestFlight 周新增 | < 20/周 | < 50/周 |
| 累计 Pro 付费 | < 10 | < 200 |

**Plan B 资金底线**（两条都设）：
- 🟡 **应急启动线 ¥9 万**（≈ 3 个月跑道）→ 激活备用方案
- 🔴 **硬停线 ¥3 万**（≈ 1 个月）→ 有秩序收场

**硬扛到底 ≠ 自杀式坚持** · 底线是让硬扛可持续

---

## 接下来怎么做 · Month 1 Week 1

- [ ] **两人全职确认** + **股权协议**（含 vesting / 竞业 / 回购）签字
- [ ] 公司注册启动
- [ ] 兼职顾问候选接触 + 周评审机制启动
- [ ] **金融律师付费咨询 1 次**（¥1-3 万）
- [ ] 开发环境：Mac Studio + Apple 开发者账号 + Cursor/Claude
- [ ] **技术 PoC 启动**：CTP SimNow + Metal K 线原型

---

<!-- _class: accent -->

## 我们现在需要对齐的三件事

# 1. 股权结构 buy-in
# 2. 6-9 月紧日子 buy-in
# 3. M6 生死线 buy-in

---

<!-- _class: cover -->

# 一件事做到位
# 让 Mac 用户在中国期货市场，
# 拥有一款超一流的原生交易工具。

<br>

关联文档：`D1-顶层设计.md` · `D2-阶段A执行.md` · `D3-风险与危机预案.md` · `产品设计书.md`

*v1 · 2026*
