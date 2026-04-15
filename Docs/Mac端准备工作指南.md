# Mac端准备工作指南

> 按照本文档操作，完成CTP SDK获取和SimNow模拟账号注册，为Mac端开发做好准备。

---

## 概念说明

```
你的App ──CTP SDK──→ SimNow模拟服务器（免费，模拟资金）
                  └→ 期货公司真实服务器（上线后，真实资金）
```

- **CTP（综合交易平台）**：上海期货交易所子公司「上期技术」开发的标准交易接口。国内90%期货公司用它。你的App通过CTP连接期货公司服务器，获取行情和下单。
- **CTP SDK**：一组C++头文件 + 动态链接库（.dylib），你的App需要链接它才能连期货服务器。
- **SimNow**：上期技术提供的免费模拟交易环境，行情和交易规则与真实期货完全一致，使用模拟资金，开发者用它测试程序。
- **openctp**：社区开源项目，提供CTP的替代模拟环境，在SimNow不可用时可作为备用。

---

## 第一步：注册SimNow模拟账号

### 1.1 注册

1. 打开 [SimNow官网](https://www.simnow.com.cn/)
2. 点击页面右上角「注册」按钮
3. 填写以下信息：
   - 手机号码
   - 短信验证码
   - 用户名
   - 密码
4. 点击「注册」完成

> **重要提醒**：
> - SimNow官网在**周末和节假日经常无法访问**，请在**工作日白天**操作
> - 注册成功后会获得 **2000万模拟资金**
> - 手机短信会收到你的 **InvestorID（投资者代码）**，务必保存

### 1.2 首次修改密码

注册后**必须修改一次密码**才能正常使用：

1. 访问 [SimNow修改密码页面](https://www.simnow.com.cn/static/resetPWDPage.action)
2. 输入手机号、验证码
3. 设置新密码
4. 完成

### 1.3 记录连接参数

注册完成后，记录以下信息（后续开发配置需要）：

```
你的个人信息（注册后获得）：
├── InvestorID:  ________（手机短信中获取，纯数字）
├── Password:    ________（你设置的密码）
└── 其他参数（SimNow环境固定，所有人一样）：
    ├── BrokerID:   9999
    ├── AppID:      simnow_client_test
    └── AuthCode:   0000000000000000（16个0）
```

### 1.4 SimNow服务器地址

SimNow提供两套环境，按需使用：

**环境一：标准环境（交易时段可用，行情与真实市场同步）**

| 组别 | 交易前置 | 行情前置 | 线路 |
|------|---------|---------|------|
| 第1组 | `tcp://180.168.146.187:10201` | `tcp://180.168.146.187:10211` | 电信 |
| 第2组 | `tcp://180.168.146.187:10202` | `tcp://180.168.146.187:10212` | 电信 |
| 第3组 | `tcp://218.202.237.33:10203` | `tcp://218.202.237.33:10213` | 移动 |

交易时段：与真实期货市场一致
- 日盘：9:00-15:00
- 夜盘：21:00-次日02:30（品种不同结束时间不同）

**环境二：7x24小时环境（随时可用，回放行情）**

| 用途 | 交易前置 | 行情前置 |
|------|---------|---------|
| 全天可用 | `tcp://180.168.146.187:10130` | `tcp://180.168.146.187:10131` |

可用时段：
- 交易日：16:00 ~ 次日09:00
- 非交易日：全天

> **开发建议**：日常开发调试用7x24环境（随时可测），功能验证用标准环境（真实行情）

---

## 第二步：获取CTP SDK

### 2.1 获取渠道

有两个渠道，任选其一：

**渠道A：SimNow官网下载（官方）**

1. 登录 [SimNow官网](https://www.simnow.com.cn/)
2. 找到「API下载」或「软件下载」入口
3. 下载最新版CTP API（选择macOS版本）
4. 版本要求：≥ 6.6.7（该版本开始支持macOS arm64）

> 注意：SimNow官网周末/节假日可能无法访问

**渠道B：openctp社区下载（推荐，更稳定）**

1. 访问 [openctp GitHub](https://github.com/openctp/openctp)
2. 在仓库中找到CTPAPI目录，下载对应版本
3. 或通过PyPI查看版本信息：[openctp-ctp on PyPI](https://pypi.org/project/openctp-ctp/)

**渠道C：期货公司官网**

部分期货公司官网提供CTP API下载，如：
- 各期货公司的「软件下载」页面
- 通常在「量化交易」或「程序化交易」分类下

### 2.2 SDK包含的文件

下载解压后，你会得到这些文件：

```
CTP SDK 目录结构：
├── ThostFtdcMdApi.h              ← 行情接口头文件（核心）
├── ThostFtdcTraderApi.h          ← 交易接口头文件（核心）
├── ThostFtdcUserApiDataType.h    ← 数据类型定义
├── ThostFtdcUserApiStruct.h      ← 数据结构定义（合约、委托、持仓等）
├── libthostmduserapi_se.dylib    ← 行情动态库（macOS，核心）
├── libthosttraderapi_se.dylib    ← 交易动态库（macOS，核心）
├── error.dtd                     ← 错误码定义
└── error.xml                     ← 错误码XML
```

> **确认要点**：
> - 确认 `.dylib` 文件是macOS版本（不是 `.so` Linux版本）
> - 如果你的Mac是Apple Silicon（M1/M2/M3/M4），确认是 `arm64` 版本
> - 可以用 `file libthostmduserapi_se.dylib` 命令查看架构信息

### 2.3 放置SDK文件

将SDK文件放到项目的指定目录：

```bash
# 1. 拉取最新代码
cd /path/to/macos_futures_trading
git pull

# 2. 创建CTP库目录
mkdir -p Sources/CTPBridge/CTPLib

# 3. 复制SDK文件到项目中
cp /path/to/ctp-sdk/ThostFtdc*.h Sources/CTPBridge/CTPLib/
cp /path/to/ctp-sdk/libthostmduserapi_se.dylib Sources/CTPBridge/CTPLib/
cp /path/to/ctp-sdk/libthosttraderapi_se.dylib Sources/CTPBridge/CTPLib/

# 4. 确认文件到位
ls -la Sources/CTPBridge/CTPLib/
```

> 注意：`.dylib` 文件不要提交到Git（已在.gitignore中排除），头文件可以提交

---

## 第三步（备用）：openctp模拟环境

如果SimNow无法注册或无法访问，可以使用openctp提供的替代模拟环境：

### 3.1 注册openctp账号

1. 微信搜索关注公众号「openctp」
2. 在公众号回复对应关键词获取账号：
   - 回复 `注册24` → 获取7x24环境账号
   - 回复 `注册仿真` → 获取仿真环境账号
3. 注册即时生效，初始资金1000万

### 3.2 openctp连接参数

```
BrokerID:   （不需要填写）
AppID:      （不需要填写）
AuthCode:   （不需要填写）
```

**7x24环境：**

| 用途 | 地址 |
|------|------|
| 交易前置 | `tcp://121.37.80.177:20002` |
| 行情前置 | `tcp://121.37.80.177:20004` |

**仿真环境（交易时段可用）：**

| 用途 | 地址 |
|------|------|
| 交易前置 | `tcp://121.36.146.182:20002` |
| 行情前置 | `tcp://121.36.146.182:20004` |

> openctp使用CTPAPI兼容接口，代码无需修改，只需切换前置地址即可

---

## 第四步：在Mac上验证环境

完成以上步骤后，在Mac上执行：

```bash
# 1. 拉取最新代码
git clone https://github.com/ethanzhang2025/macos_futures_trading.git
cd macos_futures_trading

# 2. 确认Swift工具链
swift --version
# 期望输出：Swift version 5.9+ 或 6.0+

# 3. 编译核心模块（不含CTP，验证代码完整性）
swift build
# 期望输出：Build complete!

# 4. 运行测试
swift test
# 期望输出：94 tests passed

# 5. 确认CTP SDK文件已放置
ls Sources/CTPBridge/CTPLib/*.dylib
# 期望输出：两个.dylib文件

# 6. 确认dylib架构正确
file Sources/CTPBridge/CTPLib/libthostmduserapi_se.dylib
# Apple Silicon期望输出包含：arm64
# Intel Mac期望输出包含：x86_64
```

全部通过后，即可开始Stage 1：编写CTP封装层，连接SimNow。

---

## 检查清单

完成以下所有项目后，Mac端准备工作就绪：

```
□ SimNow账号已注册
□ SimNow密码已修改（首次必须修改）
□ InvestorID已记录
□ CTP SDK已下载（macOS版本）
□ 确认.dylib文件架构正确（arm64或x86_64）
□ SDK文件已放到 Sources/CTPBridge/CTPLib/
□ git pull 拉取最新代码
□ swift build 编译通过
□ swift test 94个测试通过
□ （备用）openctp账号已注册（如果SimNow不可用）
```

---

## 常见问题

### Q: SimNow官网打不开？
A: SimNow在周末和节假日经常关闭。请在工作日白天访问。如果急需测试，使用openctp的7x24环境替代。

### Q: 下载的dylib是x86_64的，但我的Mac是Apple Silicon？
A: macOS的Rosetta 2可以运行x86_64的程序，但性能不如原生arm64。建议寻找arm64版本的SDK。CTP API从6.6.7版本开始提供macOS arm64支持。

### Q: CTP SDK版本选哪个？
A: 选最新的稳定版（当前推荐6.7.x系列）。版本越新，穿透式监管支持越完善，兼容性越好。

### Q: openctp和SimNow的区别？
A: 功能上几乎一致（都使用CTPAPI兼容接口），代码无需修改。区别：
- SimNow是官方出品，行情更真实
- openctp是社区维护，7x24可用，注册更方便
- 开发阶段两者都能用，上线时连真实期货公司的CTP

### Q: 需要期货账户才能用SimNow吗？
A: 不需要。SimNow是独立的模拟系统，任何人都可以注册使用，不需要在期货公司开户。
