// FuturesContextualDemo · 第 19 个真数据 demo（B1 Step 2 兑现）
//
// 用途：
// - 用 Sina 真行情（RB0 60min K 线）跑 v6.0+ 新交付的 4 个 ContextualIndicator
// - 模拟 FuturesContext（dailyLimits 上一日 close±7% · dailySettlements 当日末
//   close · deliveryDate 2026-10-15 · tradingHours TradingCalendar 派生）
// - 验证 LimitPriceLines / DeliveryCountdown / SettlementPriceLine /
//   SessionDivider 在真数据下工作
// - M5 Mac UI 集成预演 + 销售/合规演示物料
//
// 拓扑（4 段）：
//   段 1 · 拉 Sina K 线 + 解析 barTimes（Asia/Shanghai 时区）
//   段 2 · 构造 FuturesContext 模拟数据
//   段 3 · 跑 4 ContextualIndicator + 末值打印
//   段 4 · 总结
//
// 运行：swift run FuturesContextualDemo
// 注意：需 Sina 网络访问

import Foundation
import Shared
import DataCore
import IndicatorCore

@main
struct FuturesContextualDemo {

    // MARK: - 常量

    private static let symbol = "RB0"
    private static let productID = "RB"
    private static let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    private static let dtFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.timeZone = timeZone
        return df
    }()

    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = timeZone
        return df
    }()

    private static let chinaCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }()

    static func main() async throws {
        printSection("FuturesContextualDemo（第 19 个真数据 demo · RB0 60min × 4 ContextualIndicator）")

        // ─────────────── 段 1 ───────────────
        printSection("段 1 · 拉 Sina RB0 60min K 线 + 解析 barTimes")
        let sina = SinaMarketData()
        let bars = try await sina.fetchMinute60KLines(symbol: symbol)
        guard !bars.isEmpty else { print("❌ 0 K 线，退出"); return }

        let kline = KLineSeries(
            opens: bars.map { $0.open },
            highs: bars.map { $0.high },
            lows: bars.map { $0.low },
            closes: bars.map { $0.close },
            volumes: bars.map { Int($0.volume) },
            openInterests: bars.map { Int($0.openInterest) }
        )
        let barTimes = bars.map { dtFormatter.date(from: $0.date) ?? Date() }
        print("  ✅ \(bars.count) 根 · 最早 \(bars.first!.date) ～ 最新 \(bars.last!.date)")
        print("  ✅ barTimes 首/末：\(format(barTimes.first!)) / \(format(barTimes.last!))")

        // ─────────────── 段 2 ───────────────
        printSection("段 2 · 构造 FuturesContext（模拟 dailyLimits ±7% · Settlements · deliveryDate 2026-10-15）")
        let dailyData = aggregateDaily(bars: bars, barTimes: barTimes)
        let dailyLimits = computeDailyLimits(dailyData: dailyData)
        let dailySettlements = dailyData.map { entry in
            DailySettlement(tradingDay: entry.day, settlementPrice: entry.close)
        }
        let deliveryDate = dayFormatter.date(from: "2026-10-15") ?? Date()
        let tradingHours = TradingCalendar.tradingHours(for: productID, exchange: .SHFE)
        let rbSpec = ProductSpec(
            exchange: "SHFE", productID: productID, name: "螺纹钢", pinyin: "luowengang",
            multiple: 10, priceTick: "1", marginRatio: "0.08",
            unit: "吨", nightSession: "21:00-23:30"
        )
        let ctx = FuturesContext(
            instrumentID: "RB2510", productSpec: rbSpec,
            tradingHours: tradingHours,
            deliveryDate: deliveryDate,
            dailyLimits: dailyLimits, dailySettlements: dailySettlements
        )
        print("  ✅ \(dailyData.count) 个交易日 · \(dailyLimits.count) dailyLimits · \(dailySettlements.count) dailySettlements")
        print("  ✅ deliveryDate=2026-10-15 · tradingHours.sessions=\(tradingHours.sessions.count) 段")

        // ─────────────── 段 3 ───────────────
        printSection("段 3 · 跑 4 ContextualIndicator")

        // WHY 不抽泛型循环：4 indicator 输出 series 数不同（limit=2 / 其他=1）+ 末值打印格式不同 · 抽出反损可读
        let limit = try LimitPriceLines.calculate(kline: kline, barTimes: barTimes, context: ctx, params: [])
        let delivery = try DeliveryCountdown.calculate(kline: kline, barTimes: barTimes, context: ctx, params: [])
        let settle = try SettlementPriceLine.calculate(kline: kline, barTimes: barTimes, context: ctx, params: [])
        let session = try SessionDivider.calculate(kline: kline, barTimes: barTimes, context: ctx, params: [])

        // WHY `?? nil`：[Decimal?].last 返回 Decimal??，需摊平到 Decimal? 再喂 fmt（与 MaiYuYanFormulaDemo 一致）
        print("  📊 末根 close = \(fmt(bars.last!.close))")
        print("  · LimitPriceLines · UPPER 末值=\(fmt(limit[0].values.last ?? nil)) · LOWER 末值=\(fmt(limit[1].values.last ?? nil))")
        print("  · DeliveryCountdown · DAYS 末值=\(fmt(delivery[0].values.last ?? nil))")
        print("  · SettlementPriceLine · SETTLE 末值=\(fmt(settle[0].values.last ?? nil))")

        let inSessionCount = session[0].values.lazy.compactMap { $0 }.filter { $0 == 1 }.count
        let totalCount = session[0].values.count
        print("  · SessionDivider · IN_SESSION 末值=\(fmt(session[0].values.last ?? nil)) · 整段触发=\(inSessionCount)/\(totalCount)")

        // ─────────────── 段 4 ───────────────
        let allOK = (limit[0].values.last ?? nil) != nil
            && (delivery[0].values.last ?? nil) != nil
            && (settle[0].values.last ?? nil) != nil
            && (session[0].values.last ?? nil) != nil
            && inSessionCount > 0
        printSection(allOK
            ? "🎉 第 19 个真数据 demo 通过（4 ContextualIndicator × \(bars.count) 根真行情 × 模拟 FuturesContext）"
            : "⚠️  FuturesContextualDemo 验收未达标")
    }

    // MARK: - 数据 helper

    /// 按交易日聚合：当日最后一根 K 线 close 作为该日代表
    /// WHY 后写覆盖前写：barTimes 升序遍历 → dict[dayDate] 最终落到当日末根 close · 是项目惯用法（见 SettlementDemo）
    static func aggregateDaily(bars: [SinaKLineBar], barTimes: [Date]) -> [(day: Date, close: Decimal)] {
        var dict: [Date: Decimal] = [:]
        for (i, time) in barTimes.enumerated() {
            let comps = chinaCalendar.dateComponents([.year, .month, .day], from: time)
            if let dayDate = chinaCalendar.date(from: comps) {
                dict[dayDate] = bars[i].close
            }
        }
        return dict.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// 涨跌停 = 上一日 close ± 7%（首日 fallback 用当日 close · 演示物料不强求精确）
    /// WHY ±7%：螺纹钢实际涨跌停规则随交易所通知调整（5%~10%），demo 取中间档 7% 仅为可视化
    static func computeDailyLimits(dailyData: [(day: Date, close: Decimal)]) -> [DailyLimit] {
        let pct = Decimal(string: "0.07") ?? 0
        var result: [DailyLimit] = []
        for i in 0..<dailyData.count {
            let prevClose = i > 0 ? dailyData[i - 1].close : dailyData[i].close
            result.append(DailyLimit(
                tradingDay: dailyData[i].day,
                upperLimit: prevClose * (1 + pct),
                lowerLimit: prevClose * (1 - pct)
            ))
        }
        return result
    }

    // MARK: - 打印 helper

    static func format(_ date: Date) -> String { dtFormatter.string(from: date) }

    static func fmt(_ value: Decimal?) -> String {
        guard let v = value else { return "nil" }
        return fmt(v)
    }

    static func fmt(_ value: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 2
        return nf.string(from: value as NSDecimalNumber) ?? "?"
    }

    static func printSection(_ title: String) {
        print("─────────────────────────────────────────────")
        print(title)
        print("─────────────────────────────────────────────")
    }
}
