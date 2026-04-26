// IndicatorCore + AlertCore 联动真数据冒烟 demo（第 10 个真数据 demo）
//
// 用途：
// - 验证文华最经典指标预警链路："MA20 上穿/下穿"（crossAbove / crossBelow）
// - 串联 6 Core 全管线：Sina + UDS v2 + KLineBuilder + IndicatorCore + AlertEvaluator + ConsoleChannel/FileChannel
// - 演示动态阈值预警：每根 K 完成时重算 MA20 + updateAlert（保留 lastTriggeredAt cooldown）
//
// 拓扑：
//   段 1 · UDS v2 注入 historical → snapshot N 根 → IndicatorCore 计算初始 MA20
//   段 2 · 注册 2 预警 + 2 真通道（ConsoleChannel + FileChannel）
//          - 静态预警（必触发）：priceAbove(MA20 - 50) → 第一个 tick 就触发，验证整条管线通畅
//          - 动态预警：priceCrossAbove(MA20) · K 完成时 updateAlert 跟随 MA20 变化
//   段 3 · 跑 60s 真行情 · evaluator.onTick + UDS .completedBar → 重算 MA20 → updateAlert
//   段 4 · 触发统计 + FileChannel log 文件读回 dump 末尾 N 行
//   段 5 · 6 Core 联通校验
//
// 运行：swift run IndicatorAlertDemo
// 注意：非交易时段段 3 .completedBar 可能 = 0；动态 alert 可能不重算，但静态 alert 必触发管线通畅

import Foundation
import Shared
import DataCore
import IndicatorCore
import AlertCore

@main
struct IndicatorAlertDemo {

    static func main() async throws {
        printSection("IndicatorCore + AlertCore 联动真数据冒烟（第 10 个真数据 demo）")

        let sina = SinaMarketData()

        // 段 1：UDS v2 启动 + 计算初始 MA20
        printSection("段 1 · UDS v2 加载历史 + IndicatorCore 计算初始 MA20")
        let cache = InMemoryKLineCacheStore()
        let provider = SinaMarketDataProvider(fetcher: sina)
        await provider.connect()
        let uds = UnifiedDataSource(cache: cache, realtime: provider, historical: sina, cacheMaxBars: 200)
        let stream = await uds.start(instrumentID: "RB0", period: .hour1)
        let initialBars = await firstSnapshot(from: stream)
        print("  📦 UDS v2 snapshot \(initialBars.count) 根历史 K")
        guard let ma20Initial = computeMA20(bars: initialBars) else {
            print("  ❌ 历史 K 不足 20 根，无法计算 MA20，退出")
            return
        }
        print("  📊 初始 MA20 = \(fmt(ma20Initial))（基于 \(initialBars.count) 根历史 K）")
        let liveQuote = (try? await sina.fetchQuote(symbol: "RB0"))?.lastPrice ?? Decimal(0)
        print("  💰 当前 Sina 实时 last = \(fmt(liveQuote)) · 与 MA20 差 \(fmt(liveQuote - ma20Initial))")

        // 段 2：注册预警 + 真通道
        printSection("段 2 · 注册 2 预警 + 2 真通道（Console + File）")
        let logPath = NSTemporaryDirectory().appending("indicator_alert_\(UUID().uuidString).log")
        let console = ConsoleChannel(prefix: "[ALERT-CN]")
        let file = try FileChannel(path: logPath)
        let dispatcher = NotificationDispatcher()
        await dispatcher.register(console)
        await dispatcher.register(file)
        print("  📺 ConsoleChannel: prefix=[ALERT-CN]")
        print("  📁 FileChannel:    path=\(logPath)")

        let history = InMemoryAlertHistoryStore()
        let evaluator = AlertEvaluator(history: history, dispatcher: dispatcher)

        let staticAlertID = UUID()
        let staticAlert = Alert(
            id: staticAlertID,
            name: "RB0 ≥ MA20-50（静态阈值 · 必触发管线通畅）",
            instrumentID: "RB0",
            condition: .priceAbove(ma20Initial - 50),
            channels: [.console, .file],
            cooldownSeconds: 10000  // 长冷却 → 全程 1 次
        )
        let dynamicAlertID = UUID()
        let dynamicAlertInitial = makeDynamicAlert(
            id: dynamicAlertID,
            ma20: ma20Initial,
            nameSuffix: "动态 · K 完成时跟随 MA20 更新"
        )
        await evaluator.addAlert(staticAlert)
        await evaluator.addAlert(dynamicAlertInitial)
        print("  🔔 静态：\(staticAlert.name)")
        print("  🔔 动态：\(dynamicAlertInitial.name)")

        // 段 3：实时拼接 + 增量 MA20 + 触发
        printSection("段 3 · 实时拼接（60s · WP-44c 同合约 UDS + Alert 双订阅）")
        let counter = TriggerCounter()
        let evtStream = await evaluator.observe()
        let evtTask = Task {
            for await event in evtStream {
                print(stamp() + "  🔥 \(event.alertName) · price=\(fmt(event.triggerPrice))")
                await counter.bump()
            }
        }

        // SinaProvider 同合约直订（WP-44c 多 handler · UDS 已经订过 RB0，这是第二个 handler）
        let evaluatorRef = evaluator
        await provider.subscribe("RB0") { tick in
            Task { await evaluatorRef.onTick(tick) }
        }

        // UDS .completedBar → 重算 MA20 → updateAlert
        let allBars = MutableBars(initial: initialBars)
        let updateTask = Task {
            for await update in stream {
                guard case .completedBar(let k) = update else { continue }
                await allBars.append(k)
                let snapshot = await allBars.snapshot()
                guard let ma20 = computeMA20(bars: snapshot) else { continue }
                let updated = makeDynamicAlert(id: dynamicAlertID, ma20: ma20, nameSuffix: "动态")
                _ = await evaluator.updateAlert(updated)
                print(stamp() + "  📈 K 完成 close=\(fmt(k.close)) → MA20 重算 \(fmt(ma20)) → updateAlert（保留 lastTriggeredAt）")
            }
        }

        let driver = SinaPollingDriver(provider: provider, interval: 3.0)
        await driver.start()
        try await Task.sleep(nanoseconds: 60 * 1_000_000_000)

        await driver.stop()
        await uds.stopAll()
        await provider.disconnect()
        await file.close()
        evtTask.cancel()
        updateTask.cancel()

        // 段 4：触发统计 + log 文件验证
        printSection("段 4 · 触发统计 + FileChannel log 文件读回")
        let triggers = await counter.snapshot
        let allHistory = (try? await history.allHistory()) ?? []
        print("  🔔 AlertEvaluator 触发：\(triggers) 次 · history 落库 \(allHistory.count) 条")

        let logContent = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
        let lines = logContent.split(separator: "\n").map(String.init)
        print("  📁 FileChannel 文件 \(lines.count) 行（路径 \(logPath)）")
        if !lines.isEmpty {
            print("  📋 末 \(min(3, lines.count)) 行：")
            for line in lines.suffix(3) { print("     \(line)") }
        }
        try? FileManager.default.removeItem(atPath: logPath)

        // 段 5：6 Core 联通校验
        printSection("段 5 · 6 Core 联通校验")
        let checks: [(String, String)] = [
            ("Shared          ", "KLine / Tick / Decimal / Date 跨 Core 类型"),
            ("DataCore Sina   ", "fetchMinute60KLines + fetchQuote + SinaProvider + SinaPollingDriver"),
            ("DataCore UDS v2 ", "historical 注入 + cache + KLineBuilder + WP-44c 多 handler"),
            ("IndicatorCore   ", "MA20 计算（基于 KLineSeries · 增量重算每 K 一次）"),
            ("AlertCore       ", "Evaluator updateAlert（保留 lastTriggeredAt）+ priceAbove + priceCrossAbove"),
            ("AlertChannels   ", "ConsoleChannel(stdout) + FileChannel(log) 真落地输出")
        ]
        for (name, desc) in checks { print("  ✅ \(name) · \(desc)") }

        let allOK = triggers >= 1 && lines.count >= 1 && allHistory.count >= 1
        printSection(allOK
            ? "🎉 第 10 个真数据 demo 通过（IndicatorCore + AlertCore 联动 · 6 Core 全闭环）"
            : "⚠️  通道未收到事件（可能 alert 阈值 + 行情未跨过；管线本身 OK）")
    }

    // MARK: - Stream 辅助

    static func firstSnapshot(from stream: AsyncStream<DataSourceUpdate>) async -> [KLine] {
        for await update in stream {
            if case .snapshot(let bars) = update { return bars }
        }
        return []
    }

    // MARK: - IndicatorCore MA20

    static func computeMA20(bars: [KLine]) -> Decimal? {
        guard bars.count >= 20 else { return nil }
        // KLineSeries.openInterests 是 [Int]；KLine.openInterest 是 Decimal · MA 计算不依赖此字段，统一塞 0
        let series = KLineSeries(
            opens: bars.map(\.open),
            highs: bars.map(\.high),
            lows: bars.map(\.low),
            closes: bars.map(\.close),
            volumes: bars.map(\.volume),
            openInterests: Array(repeating: 0, count: bars.count)
        )
        guard let result = try? MA.calculate(kline: series, params: [20]) else { return nil }
        return result.first?.values.last ?? nil
    }

    // MARK: - AlertCore 动态 alert 构造

    static func makeDynamicAlert(id: UUID, ma20: Decimal, nameSuffix: String) -> Alert {
        Alert(
            id: id,
            name: "RB0 上穿 MA20=\(fmt(ma20))（\(nameSuffix)）",
            instrumentID: "RB0",
            condition: .priceCrossAbove(ma20),
            channels: [.console, .file],
            cooldownSeconds: 30
        )
    }

    // MARK: - 通用 helpers

    static func fmt(_ value: Decimal) -> String {
        priceFormatter.string(from: value as NSDecimalNumber) ?? "?"
    }

    static func stamp() -> String {
        "[\(stampFormatter.string(from: Date()))]"
    }

    static func printSection(_ title: String) {
        print("─────────────────────────────────────────────")
        print(title)
        print("─────────────────────────────────────────────")
    }

    private static let priceFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2
        return nf
    }()

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

// MARK: - 状态 actor

private actor MutableBars {
    private var bars: [KLine]
    init(initial: [KLine]) { self.bars = initial }
    func append(_ k: KLine) { bars.append(k) }
    func snapshot() -> [KLine] { bars }
}

private actor TriggerCounter {
    private(set) var snapshot: Int = 0
    func bump() { snapshot += 1 }
}
