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
    padding: 60px 80px;
    font-size: 24px;
    line-height: 1.6;
  }
  h1 {
    color: #1A1A1A;
    font-size: 52px;
    font-weight: 700;
    letter-spacing: -0.5px;
  }
  h2 {
    color: #2563EB;
    font-size: 36px;
    font-weight: 600;
    border-bottom: 3px solid #2563EB;
    padding-bottom: 10px;
    margin-top: 0;
  }
  h3 {
    color: #1A1A1A;
    font-size: 26px;
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
    margin: 20px 0;
  }
  table {
    font-size: 20px;
    border-collapse: collapse;
    margin: 20px auto;
  }
  th {
    background: #2563EB;
    color: white;
    padding: 10px 14px;
    text-align: left;
    font-weight: 600;
  }
  td {
    padding: 10px 14px;
    border-bottom: 1px solid #E5E7EB;
  }
  code {
    font-family: 'JetBrains Mono', 'SF Mono', Consolas, monospace;
    background: #F0F4F8;
    color: #1A1A1A;
    padding: 2px 8px;
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
    font-size: 64px;
    border: none;
  }
  section.cover h2 {
    color: #FAFAFA;
    border: none;
    font-size: 32px;
  }
  section.cover p {
    color: #9CA3AF;
    font-size: 24px;
  }
  section.accent {
    background: #2563EB;
    color: white;
    padding: 80px;
  }
  section.accent h1, section.accent h2 {
    color: white;
    border: none;
  }
  .big-number {
    font-size: 80px;
    color: #2563EB;
    font-weight: 700;
    line-height: 1;
    display: block;
  }
  .metric-row {
    display: flex;
    gap: 40px;
    justify-content: center;
    align-items: center;
    margin-top: 30px;
    text-align: center;
  }
  footer {
    font-size: 14px;
    color: #999;
  }
  ul li, ol li {
    margin-bottom: 8px;
  }
---

<!-- _class: cover -->

# 中国期货 Mac/iPad
# 原生交易终端

## 为专业交易者打造的 Mac 专业工作台

*盯盘 · 预警 · 复盘 · 训练 · 日志*

2026 · 寻求天使轮 **¥200 万**

<br>

*Pitch Deck v1*

---

## 痛点 · Mac 期货用户的尴尬日常

- 中国期货活跃账户 **250 万**，Mac 渗透率 **8%** → Mac 期货用户 **≈ 20 万**
- 主流终端（文华 / 博易 / 快期）**全部 Windows 架构**，UI 停留在 2010 年代
- **85% 以上 Mac 用户被迫装 Parallels 跑文华**
- 2019 年文华开始收费（¥1880/年）→ 口碑崩坏，但无合适替代品

> "我在 Mac 上用文华，感觉像在 2012 年。但没有别的选择。" —— 一位深度交易者原话

---

## 方案 · 中国期货版 TradingView × Linear × iPad Pro

**三件事改变游戏规则**：

| 核心 | 做什么 | 对手做不到 |
|------|-------|----------|
| 🎨 **Metal 原生图表** | 60fps / 10 万根 K 线 | 文华 30fps，快期 WebView 卡顿 |
| 📝 **麦语言完整兼容** | 文华用户零成本迁移策略库 | 快期不支持，博易部分支持 |
| 📱 **Apple 三端协同** | Mac + iPad + iPhone 单账户同步 | 其他竞品不在 Apple 生态 |

---

## 市场 · 小众但高 ARPU 的精品生意

<div class="metric-row">

<div>

<span class="big-number">¥2400万</span>

**TAM** 年付费容量

</div>

<div>

<span class="big-number">¥720万</span>

**SAM** 10 年可及 ARR

</div>

<div>

<span class="big-number">¥2000万+</span>

**SOM** M24 目标 ARR

</div>

</div>

<br>

**推导**：250 万期货活跃 × 8% Mac × 30% Pro 付费意愿 × ¥399 年费 = ¥2400 万 TAM

---

## 产品 · Stage A "专业工作台"

**图表核心**
- Metal 引擎 · 60fps / 56 指标（含期货特有 12 个 TradingView 没有）
- 画线 6 种 · 趋势 / 水平 / 斐波那契 / 平行通道 等

**工作流 5 大模块**（Stage A 差异化）
- **🔔 条件预警中心** · 价格/画线/异常提醒
- **📝 交易日志** · 半自动生成 + 手动补原因情绪
- **🎮 模拟训练** · 接 SimNow 零成本入门
- **⏮️ K 线回放** · 沉浸式复盘体验
- **🗂️ 工作区模板** · 多布局一键切换

**复盘 + 战略储备**
- 复盘 8 图（品种热力矩阵 + 时段分析）
- 麦语言 · Stage A 基础 30-50 函数 → Stage B 95%+
- iPad 专业工作流 · 6 大独家场景（Stage B）

---

## 商业模式 · B2C 主 + B2B2C 代付辅

**定价**：Free · Pro **¥399/年** · Pro Max **¥999/年**（Stage B）

**B2B2C 买单方 4 类**（Stage B 启动 · 产品不分化）
- 期货公司总部（决策慢但单价高）
- **营业部（决策快，优先谈）**
- 大客户团队 / 高净值服务体系

**单位经济**：CAC < ¥200 · LTV > ¥1500 · **LTV/CAC > 7.5** · Pro 毛利 > 85%

---

## 牵引力 · Stage A 9 个月路径

| 月份 | 里程碑 |
|------|-------|
| M1-M5 | 开发 + 内测 · TestFlight 累计 400 人 |
| **M6** | **Pro 订阅上线 · 生死节点** |
| M7-M8 | 运营 + 迭代 · Pro 付费 300 人 |
| M9 | **500 Pro / 月流水 ¥1.7 万 / 盈亏平衡** |
| M12 | Stage B 启动（CTP 下单）|
| M18 | 麦语言完整兼容上线 |
| M24 | **ARR ¥2000 万+ / 3-5 家券商合作** |

---

## 竞争 · 1-3% 市占就是好生意

| 竞品 | 市占 | Mac | 年价 | 麦语言 | 审美 |
|------|:---:|:---:|:---:|:---:|:---:|
| 文华赢顺 | 70-80% | ❌ | ¥1880 | ✅✅ | ★ |
| 博易大师 | 10-15% | ❌ | 券商绑 | 部分 | ★ |
| 快期 V4 | 5-10% | ⚠️简陋 | 免费 | ❌ | ★★ |
| 交易开拓者 | < 5% | ❌ | ¥1680 | 自有 | ★★ |
| **我们** | **目标 1-3%** | **✅** | **¥399** | **渐进→95%** | **★★★★★** |

**我们不抢文华的 Windows 用户。我们抢 Mac 上装 Parallels 的那 20 万。**

---

## 团队 · 小而精的 Hunter 组合

**CEO（创始人）**
- 期货交易者 10+ 年 · 软件工程师
- **AI 辅助编码**：Swift / SwiftUI / Metal
- 产品最终决策权

**COO（合伙人）**
- **Hunter 型销售**：擅长 1v1 冷启动外联
- 用户访谈 + VIP 运营 + BD

**兼职顾问**：产品 / 设计师，每周 4-6h 评审

**团队演进**：Stage A 3-4 人 → Stage B 8-12 人（按里程碑招聘）

---

## 财务 · 3 年 P&L（三档情景）

| 年 | 阶段 | 保守 ARR | 乐观 ARR | 净利（保守）|
|----|-----|---------|---------|----------|
| Y1 | Stage A | ¥30 万 | ¥50 万 | **-¥6 万** |
| Y2 | Stage B 早 | ¥200 万 | ¥500 万 | **+¥20 万** |
| Y3 | Stage B 晚 | **¥800 万** | **¥2500 万** | **+¥320 万** |

**乐观场景的关键触发器**：**麦语言完整兼容** 启动文华深度用户迁移潮

**盈亏平衡**：M11-M12 月度现金流为正

---

<!-- _class: accent -->

## The Ask

# 天使轮 **¥200 万**

**估值**：¥2500 万 pre-money · 稀释 **8%**

**用途**：
- **60% 工程**（Stage A 收尾 + Stage B 启动）
- **20% 合规 + 保险**（Stage B 下单前置）
- **15% GTM** + 用户获取
- **5%** 储备

**下个里程碑（12 月）**：ARR ¥100 万 · 启动种子轮

---

<!-- _class: cover -->

# 让 Mac 用户
# 在中国期货市场，
# 拥有一款超一流的原生交易工具。

<br>

Contact · [邮箱 / 微信]

*Deck v1 · 2026*
