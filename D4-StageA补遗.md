# D4 · Stage A 补遗与深化

> 本文档补齐 D1/D2/D3 + 产品设计书审阅后发现的 12 条设计遗漏（gap）。内容深度议题集中在此，小改动已原地回写相关文档，执行项已加入 `Stage A 工作包清单.md`。
>
> **前置阅读**：D1 / D2 / D3 / 产品设计书
> **版本**：v1.0 · 2026-04-24
> **审阅来源**：`/home/beelink/.claude/plans/greedy-wishing-frog.md`

---

## 速查表

| # | 议题 | 严重性 | 落地方式 | 时点 |
|---|------|-------|--------|------|
| G1 | CloudKit 数据主权合规 | 🔴 | D4 详述 + WP-84 新增 | M1 律咨 + M4-M5 落地 |
| G2 | WAPU 埋点 schema | 🔴 | D4 详述 + WP-133 新增 | M1 末 |
| G3 | iPhone 战略冲突 | 🔴 | 原地改 D1/产品设计书 + 话术统一 | 立即 |
| G4 | 文华用户数据迁移 | 🔴 | D4 详述 + WP-63/64 新增 | M8 |
| G5 | 开票 / 发票 | 🔴 | D4 详述 + WP-94 新增 | M6 |
| G6 | 期货软件备案 | 🟡 | 并入 WP-02 律师咨询 | M1 |
| G7 | Apple 审核拒审防御 | 🟡 | D4 详述 + 并入 WP-05 | M5 |
| G8 | 套利 / 期权观察器 | 🟡 | **决定不做**，留存理由 | Stage B 视情况 |
| G9 | M6 Pre-launch Checklist | 🟡 | D4 详述 + WP-95 新增 | M5 末 |
| G10 | 创始人关键人风险 | 🟡 | 原地改 D3 §7 + SOP | M1 |
| G11 | 本地数据加密范围 | 🟡 | 原地改产品设计书 9.2 | M5 前 |
| G12 | 多设备绑定策略 | 🟡 | D4 详述 + 并入 WP-91 | M6 |
| G13 | 用户数据导出 | 🟢 | Stage B 前补 | — |
| G14 | 订阅服务降级 | 🟢 | Stage B 前补 | — |

---

## G1 · CloudKit 数据主权合规方案

### 问题
D2 §4 将 CloudKit 定为云同步方案（"Apple 生态零运维"）；但 CloudKit 默认存 Apple 境外服务器（美国/爱尔兰）。与合规 9.2 "数据存储境内 + AES-256 加密"及《个保法》第 40 条、《数据安全法》境内存储要求冲突。金融类 App 尤其敏感。

### 三种备选

**方案 A · 分级存储（推荐作默认预案）**
- CloudKit 只存**非敏感数据**：UI 布局、工作区模板、自选合约代码列表（不含持仓）、画线几何参数
- **敏感数据**（交易日志 / 预警记录 / 账户关联信息 / 资金快照）→ 阿里云自建同步
- 优点：保留 CloudKit 对 UI 偏好的零运维；敏感数据合规
- 工作量：+0.5-1 人月（需搭简易同步服务）

**方案 B · 完全阿里云自建**
- 放弃 CloudKit，所有同步走阿里云
- 优点：合规最稳、后端数据观测能力强
- 缺点：+1-1.5 人月工程量，后端运维负担上升
- 适用：律师认定 CloudKit 存在明确违法风险时

**方案 C · 数据出境安全评估**
- 走《数据出境安全评估办法》流程申请
- 成本：¥10-30w + 6-12 月；不适合 Stage A

### 决策流程
1. **M1 WP-02 律师咨询** 专项问清：CloudKit 在期货类个人交易日志场景是否触及个人信息出境线
2. 律师结论分三种情况：
   - 明确 No-Go → 执行方案 B
   - 边界模糊但建议规避 → 执行方案 A（推荐）
   - 明确合法 → 维持 CloudKit 全量（不推荐，风险自留）
3. **M1 末拍板**，写回 D2 §4 与产品设计书 9.2

### 工程实现要点（方案 A）
- 数据模型分层：`CloudKitSyncable` protocol vs `SelfHostedSyncable` protocol
- CloudKit 字段 Schema 预埋时只为非敏感模型预留
- 阿里云自建同步 API：RESTful + HTTPS + Device Token 鉴权 + 冲突解决用 Last-Write-Wins
- 阿里云部署在境内 Region（杭州 / 北京），OSS 加密桶

### 落地
- 新增 WP-84 · CloudKit 合规方案落地（M4-M5）
- D2 §4 技术栈表 CloudKit 行补注："**敏感数据阿里云自建，非敏感数据 CloudKit；详 D4 G1**"
- 产品设计书 3.1 ⑨ / 9.2 同步注脚

---

## G2 · WAPU 埋点 schema

### 问题
D1 §4 定义 WAPU 为"7 天内至少打开 3 次的有效 Pro 订阅用户"，但没定义埋点事件；产品设计书 3.3 仅抽象说"自建 SQLite"。M1 末启用 WP-130 看板时会拿不到数据。

### 核心事件（10 个，M1 末前落地）

| # | 事件名 | 触发 | 关键字段 |
|---|-------|------|---------|
| 1 | `app_launch` | App 冷启动 | user_id, device_id, app_version, launch_source（cold/hot）|
| 2 | `session_start` | 进入前台，距上次 session_end > 3 分钟 | user_id, device_id, session_id |
| 3 | `session_end` | 进入后台或退出 | session_id, duration_sec |
| 4 | `chart_open` | 打开图表 | session_id, contract_code, period |
| 5 | `indicator_add` | 添加指标 | session_id, indicator_id |
| 6 | `drawing_create` | 画线 | session_id, drawing_type |
| 7 | `replay_start` | K 线回放开始 | session_id, contract_code, date |
| 8 | `alert_trigger` | 预警触发（客户端判断） | alert_id, contract_code, type |
| 9 | `journal_entry_save` | 交易日志条目保存 | session_id, entry_id |
| 10 | `subscription_event` | 订阅状态变更 | user_id, event_type（start/renew/cancel/expire）, sku |

### SQLite 表结构

```sql
CREATE TABLE events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  session_id TEXT,
  event_name TEXT NOT NULL,
  event_ts INTEGER NOT NULL,      -- Unix 毫秒
  props_json TEXT,                 -- 灵活字段
  app_version TEXT,
  uploaded INTEGER DEFAULT 0       -- 是否已上报后端
);
CREATE INDEX idx_events_user_ts ON events(user_id, event_ts);
CREATE INDEX idx_events_name_ts ON events(event_name, event_ts);
```

上报机制：本地写入 → 后端 REST 批量接收（每 5 分钟或 100 条）→ 后端入 PostgreSQL。

### WAPU 查询模板（后端 PostgreSQL）

```sql
-- 某周 WAPU（过去 7 天内 session_start ≥ 3 次的 Pro 用户数）
WITH pro_users AS (
  SELECT user_id FROM subscriptions
  WHERE expire_at > NOW() AND status = 'active'
),
weekly_opens AS (
  SELECT user_id, COUNT(DISTINCT DATE(event_ts)) AS open_days
  FROM events
  WHERE event_name = 'session_start'
    AND event_ts >= NOW() - INTERVAL '7 days'
    AND user_id IN (SELECT user_id FROM pro_users)
  GROUP BY user_id
)
SELECT COUNT(*) AS wapu
FROM weekly_opens
WHERE open_days >= 3;
```

"至少打开 3 次"严谨定义：**过去 7 天内 ≥ 3 个不同日期有 session_start**（避免同日多次开计为多次）。

### 隐私
- **不收集**交易订单内容、资金金额、持仓明细
- 用户可在设置里一键关闭埋点（上传）
- 隐私政策披露采集事件 list

### 落地
- 新增 WP-133 · 埋点 schema 与上报链路（M1 末启用）
- D3 §1 WP-130 看板说明补一句"依赖 WP-133 埋点已落地"

---

## G3 · iPhone 战略澄清（决策已拍板）

### 冲突
- D1 §2.5 差异化 4 写"Mac + iPad + iPhone 协同"
- D2 §2 "绝对不做"明写 ❌ iPhone 版
- 产品设计书 3.1 把 iPhone 列 Stage B 无时点

### 决策：**Stage A 仅 Mac + iPad，iPhone 推到 Stage B 初**

**理由**：
- 资源约束下再加 iPhone 客户端即便轻量也是 2-3 周，挤占 M8 麦语言与 M9 冲刺
- 产品原则冲突优先级：稳定 > 速度 > 现金 > 节奏。加 iPhone 挤压稳定性
- M9 北极星冲刺阶段不应分散精力

### 对外话术统一
**Stage A 阶段（M0-M9）**：
- ✅ "Mac + iPad 原生专业工作台"
- ✅ "单账户两端同步"
- ❌ 不用"Mac + iPad + iPhone 三端" · 避免用户预期错位

**Stage B 阶段起**：启用三端叙事。

### 原地修订（下方文档将回写）
- D1 §2.5 差异化 4：改为 "Mac + iPad 协同（单账户两端同步）· Stage B 起加入 iPhone"
- 产品设计书 3.1 功能全景图：iPhone 行在 Stage A 列标"❌"，Stage B 列"基础伴侣版"
- 产品设计书 4.2 / 官网话术：统一"Mac + iPad 专业工作台"

---

## G4 · 文华用户数据迁移路径

### 问题
现有迁移入口仅**交割单 CSV**（WP-53 交易日志）。P3 文华迁移者还有三类数据：
1. **自选合约列表**（`.wh5` 二进制格式）
2. **自定义麦语言公式**（`.wh` 文本格式，与 Legacy FormulaEngine 兼容）
3. **画线数据**（文华专有格式，结构复杂）

### 方案分层

**Tier 1（Stage A M8，必做）**
- 导入 `.wh` 公式文件：与 WP-62 麦语言基础版同步实现，可直接复用 Lexer
- 导入文华自选列表：逆向 `.wh5` 格式，支持批量合约代码导入（若格式复杂，降级做"手动粘贴合约代码列表"）

**Tier 2（Stage B 初）**
- 画线数据迁移：文华画线格式繁多，Stage A 不做，Stage B 启动后视 P3 转化率决定

### 话术规避（D1 §5 红线）
- ✅ "支持导入麦语言公式文件"
- ✅ "自选合约一键导入"
- ❌ 不得宣传"无缝迁移文华"或"100% 迁移"

### 落地
- 新增 WP-63 · 文华麦语言公式导入（M8）
- 新增 WP-64 · 文华自选列表导入（M8）
- 产品设计书 3.1 模块 ⑪ 末尾补一行"支持文华 .wh 公式与自选列表导入，降低 P3 迁移摩擦"

---

## G5 · 开票与税务

### Stage A 方案（M6 上线即生效）
**手动开票流程**：
1. 用户发邮件至 `invoice@<domain>` 申请开票（提供抬头 / 税号 / 金额 / 订单号）
2. 合伙人在 **阿里云电子发票服务** 或 **公司代账** 处开具电子普票
3. 48 小时内发回用户邮箱
4. 记录到飞书财务表

**开票规则**：
- 仅开具订阅实际支付金额（Apple IAP 结算后金额）
- 默认开具**电子普票**（纸质增票按需 & 加收快递费）
- 免费续期、推荐奖励延期**不开票**（无实际付费）

### Stage B 方案（M12 前接入）
接入 **百望云** 或 **诺诺网** 电子发票 API：
- 用户在 App 内填写开票信息后一键索取
- 后端调 API 自动开具 → 邮件推送 PDF
- 年费 ¥2000-5000，单票成本 ¥0.3-0.5

### B2B2C 代付（Stage B）
- 营业部 / 期货公司代付 → 每月汇总开一张增值税专票给采购方
- 单客户金额小时合并开，避免税务碎片

### 落地
- 新增 WP-94 · 手动开票 SOP 与财务表模板（M6）
- 产品设计书 §7 "财务模型"末尾加 "7.5 税务与发票" 段

---

## G6 · 期货软件备案（并入律师咨询）

### 需问清
1. 本产品（期货分析 / 复盘软件，不含下单）是否需向**中期协**备案？
2. 未来 Stage B 加入 CTP 下单后是否触发**证监会金融信息系统备案**？
3. "模拟训练"功能（接 SimNow）是否被认定为"程序化交易相关软件"？
4. 是否需要加入《期货软件开发商自律承诺书》等行业组织要求？

### 落地
- 已更新 WP-02 描述："律师咨询专项问清 CloudKit 合规 + 期货软件备案 + 模拟训练合规边界"
- 结果写入产品设计书 9.1 + 本文档

---

## G7 · Apple 金融类 App 审核拒审防御

### 金融类常见拒审 Top 10 + 对策

| # | 拒审原因 | 我们的对策 |
|---|---------|---------|
| 1 | 未披露风险（Guideline 1.4.3）| App 启动首次 / 订阅页 / 关于页均显示风险提示："期货交易有风险，投资需谨慎" |
| 2 | 缺金融监管牌照证明（Guideline 5.2.1）| 上传"软件提供方"定位说明 + 律师咨询函；明确"非持牌金融机构，不提供投资建议" |
| 3 | 疑似下单功能（即使模拟）| 模拟训练明确标注 "SimNow 仿真环境，非实盘" + 独立二级界面 |
| 4 | 诱导订阅 / 暗扣（3.1.2）| 订阅页完全明示 ¥399/年、首年即付、无自动免费试用暗扣 |
| 5 | 隐私政策不完整（5.1.1）| 隐私政策列明所有采集字段、第三方 SDK、数据存储位置 |
| 6 | 非公开 API 使用 | 自检所有系统 API；避免 runtime 反射私有方法 |
| 7 | 崩溃率高（2.1）| 提交前内部用 100+ 台设备做冒烟测试 |
| 8 | 描述与功能不符（2.3.1）| App Store 描述严格按实际功能写，不夸大 |
| 9 | 涉及中国大陆用户身份验证 | 加入实名验证流程（Stage B 下单功能启用时）或声明"仅供分析使用"（Stage A）|
| 10 | App 与网站 / 营销素材不一致 | 官网 / Screenshot / 描述 / 客服话术全部对齐 |

### 预审准备
- 律师函（软件提供方身份 + 不提供投资建议声明）
- Demo 账号（审核员可登录体验）
- 对审核员的 Review Notes 模板（中英双语）

### 落地
- WP-05 · 用户协议与隐私政策 DoD 补一项："Apple 审核拒审 Top 10 对策清单已就绪"

---

## G8 · 套利 / 期权观察器（决定不做 · 留存）

### ChatGPT 建议
新探索原档 `首版产品功能建议.md` 第 6 项建议 Stage A 做一个轻量观察器（套利对价差板 + 期权 T 型报价）。

### 决策：**Stage A 不做**
**理由**：
1. M7-M9 已有 iPad + CloudKit + 麦语言三大块，时间紧
2. 套利 / 期权用户在 P1 占比小（P1 主观 Pro 交易者主打主力合约趋势）
3. 3-5 天工作量在 M9 冲刺期不值得挤占
4. 产品设计书 3.1 的 12 期货特有指标里已含"价差线 / 基差线"，对轻量套利观察已有部分覆盖

### 触发重新评估条件
- Stage B 启动后用户访谈出现高频呼声
- 或 B2B2C 营业部谈判明确需要期权观察能力

---

## G9 · M6 Pre-launch Checklist

### 分 4 大类 26 项

**技术与稳定性（8）**
1. 生产数据库备份策略验证（每日自动 + 异地）
2. Sentry 告警规则配置（崩溃率 > 0.5% 即报警）
3. 性能基准全部达标（10w K 线 60fps / 冷启动 < 1s / Tick < 1ms / 内存 < 500MB）
4. CI benchmark 规则生效（性能回归 block merge）
5. 阿里云生产环境压测（100 并发无异常）
6. CTP 行情订阅 7x24 稳定性测试（至少 3 天）
7. 断线重连 SOP 真实断网场景演练通过
8. 代码签名 / 证书有效期检查（至少还有 6 个月）

**合规与法务（6）**
9. 《用户协议》《隐私政策》律师最终审过
10. ICP 备案 / 软著下证确认
11. App Store 审核材料完整（律师函 / Demo 账号 / Review Notes）
12. 境内数据存储合规确认（详 G1）
13. 等保 2.0 预评估整改完成
14. 风险提示文案植入三处（启动 / 订阅页 / 关于页）

**商业与运营（6）**
15. IAP 订阅产品配置审核通过
16. Pro ¥399 / ¥39 双档价格上架
17. 开票 SOP 与邮箱启用（G5）
18. 退款流程演练（WP-92）
19. 客服微信群首批 200 人筹备（Pro 邀请制）
20. VIP 群规 + 合伙人话术培训

**营销与 PR（6）**
21. 官网上线 + status 页面（WP-101 / WP-123）
22. App Store 产品页 + 截图 + ASO 关键词（WP-102）
23. 少数派深度评测第二篇定稿（WP-103 · M6 末发）
24. 即刻 / V2EX 上线公告帖准备
25. 发布日 24 小时值班排班
26. 首日事故应急群建立（合伙人 + 你 + 关键兼职顾问）

### 灰度发布策略
- Day 1：仅开放给 Beta 200 人
- Day 3：若无 P0-P1 事故，开放给已注册 TestFlight 用户（~500）
- Day 7：Mac App Store 全量放开

### 落地
- 新增 WP-95 · M6 Pre-launch Checklist 执行（M5 末）
- M5 末 WP-90 上线决策会同时做 checklist 走查

---

## G10 · 创始人关键人风险

### 新增风险条（D3 §7 风险表）

| 风险 | 概率 | 影响 | 对冲 | 触发信号 |
|------|-----|-----|------|---------|
| **创始人（你）病 / 意外 1 周-1 月** | 低 | **致命** | 备用访问 + 关键 SOP 文档化 + 可选小额意外险 | 连续 3 天无法工作 |

### 对冲动作（M1 完成）

**备用访问授权**（合伙人拥有）：
- Apple 开发者账号双人团队（Account Holder 你 + Admin 合伙人）
- 代码签名密钥备份（加密后放入合伙人 1Password 或铁盒保险箱）
- GitHub 组织管理员权限
- 阿里云主账号子账户（子账户可暂停服务、回滚代码、续费账单）
- 公司对公账户 U 盾副件
- 飞书 / Linear / 域名注册商账号

**关键操作 SOP 文档化**（M1-M3 贯穿）：
- CI 发布流程
- 生产数据库备份 / 恢复
- Apple 开发者证书续期
- CTP 账号续订
- 阿里云账单处理

**可选：小额意外险**
- 意外险 ¥100-300/年
- 重疾险视个人情况

### 落地
- D3 §7 风险表新增一行（下方原地修订）
- WP-10 股权协议中增加"创始人紧急授权条款"
- WP-13 团队分工文档中增加"备用访问清单"

---

## G11 · 本地敏感数据加密范围

### 分级

| 数据类别 | 敏感级 | 加密方式 |
|---------|-------|--------|
| 用户凭证（API token / refresh token）| 🔴 高 | Keychain（Apple 系统级）|
| Apple IAP 订阅凭证 | 🔴 高 | Keychain |
| CTP 账号密码（Stage B）| 🔴 高 | Keychain |
| 交易日志（含原因 / 情绪备注）| 🟡 中 | **SQLCipher**（加密 SQLite）|
| 预警规则 | 🟡 中 | SQLCipher |
| 画线 / 自选 / 工作区模板 | 🟢 低 | 明文 SQLite（数据本身非敏感）|
| UI 偏好 / 布局 | 🟢 低 | UserDefaults |

### SQLCipher 实现要点
- 密钥由 **Keychain 生成 + 存储**，每台设备独立
- 首次启动自动生成 256-bit 随机密钥
- 密钥**不走网络同步**（即使 CloudKit）
- 换机通过 iCloud Keychain 同步（用户授权）

### 落地
- 产品设计书 9.2 补细化分级（下方原地修订）
- WP-05 实现时按本表执行

---

## G12 · 多设备绑定策略

### 规则
- **Pro 订阅：3 台设备同时激活**（典型组合：主 Mac + iPad + 备用 Mac 或 iPhone）
- Pro Max（Stage B）：**5 台**
- 第 4 台激活时：提示"已达上限，踢出最久未用设备？"

### 实现
- 后端订阅服务维护 `device_bindings` 表：user_id / device_id / device_name / last_active_at
- 客户端启动时带 device_id 验证订阅
- 超限时返回 409 Conflict，客户端提示踢出决策

### 防滥用
- Device ID 用 Apple `identifierForVendor` + 硬件指纹复合
- 每 90 天允许用户**自助重置绑定一次**
- 客服邮件可额外触发重置（每年不超过 2 次）

### 落地
- WP-91 Apple IAP 接入时同步实现
- 产品设计书 §5 定价末尾补"5.6 设备绑定策略"段

---

## G13 · 用户数据导出（Stage B 前补）

轻量实现（1-2 天）：
- 设置 → 导出我的数据
- 选项：交易日志（JSON/CSV）/ 画线 / 自选 / 工作区模板
- 打包成 zip 邮件发送或本地下载

**为什么 Stage A 末可做**：体现 D1 原则 7 "尊重用户的钱和注意力"；GDPR / 个保法第 45 条"可携权"合规加分。

---

## G14 · 订阅服务降级方案（Stage B 前补）

后端订阅服务挂了时：
- 客户端本地缓存最近一次订阅验证结果（expire_at + last_verified_at）
- 若后端不可用，允许 **≤7 天宽限期**（last_verified_at + 7d 内仍可全功能使用）
- 7 天后仍不可用 → 降级为 Free 功能集 + 全屏提示 "订阅服务暂时不可用，请稍后重试"

---

## 修订日志

| 日期 | 版本 | 修订 |
|------|------|-----|
| 2026-04-24 | v1.0 | 初稿 · 14 条 gap 详述（12 主 + 2 低危储备）|
