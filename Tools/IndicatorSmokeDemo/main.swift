// WP-41 · 指标真数据冒烟 demo
//
// 用途：
// - 用 Sina 真行情（RB0 60 分钟 K 线）跑 6 个经典指标
// - 验证 IndicatorCore 56 指标库在真实数据下出真值（不再是 mock 测试想象）
// - 暴露任何整数→Decimal / 字段缺失 / 周期未满处理的潜在问题
//
// 运行：swift run IndicatorSmokeDemo
//
// 验收：MA20 / EMA12 / MACD(12,26,9) / RSI(14) / BOLL(20,2) / KDJ(9,3,3) 末值非 nil

import Foundation
import Shared
import DataCore
import IndicatorCore

@main
struct IndicatorSmokeDemo {

    static func main() async throws {
        let symbol = "RB0"
        let symbolName = "螺纹钢"

        print("─────────────────────────────────────────────")
        print("WP-41 · 指标真数据冒烟 demo（\(symbol) \(symbolName) · 60 分钟 K 线）")
        print("─────────────────────────────────────────────")

        let sina = SinaMarketData()
        let bars = try await sina.fetchMinute60KLines(symbol: symbol)
        guard !bars.isEmpty else {
            print("❌ 拉取 0 根 K 线，退出")
            return
        }
        print("✅ 拉取 \(bars.count) 根 K 线（最早 \(bars.first!.date) ～ 最新 \(bars.last!.date)）")

        // 转 KLineSeries（列向量）
        let series = KLineSeries(
            opens: bars.map { $0.open },
            highs: bars.map { $0.high },
            lows: bars.map { $0.low },
            closes: bars.map { $0.close },
            volumes: bars.map { $0.volume },
            openInterests: bars.map { $0.openInterest }
        )

        // 计算 6 个指标
        let ma20    = try MA.calculate(kline: series, params: [20])[0]
        let ema12   = try EMA.calculate(kline: series, params: [12])[0]
        let macd    = try MACD.calculate(kline: series, params: [12, 26, 9])  // [DIF, DEA, MACD]
        let rsi14   = try RSI.calculate(kline: series, params: [14])[0]
        let boll    = try BOLL.calculate(kline: series, params: [20, 2])      // [MID, UPPER, LOWER] · 注意顺序
        let kdj     = try KDJ.calculate(kline: series, params: [9, 3, 3])     // [K, D, J]

        // 打印最近 5 根 + 末值
        let n = bars.count
        let head = "时间               开       高       低       收       MA20     EMA12    DIF      DEA      MACD     RSI14    BOLL-M   BOLL-U   BOLL-L   K        D        J"
        print("─────────────────────────────────────────────")
        print(head)

        let lastN = max(0, n - 5)
        for i in lastN..<n {
            let bar = bars[i]
            let cells: [String] = [
                bar.date.padding(toLength: 16, withPad: " ", startingAt: 0),
                fmt(bar.open), fmt(bar.high), fmt(bar.low), fmt(bar.close),
                fmt(ma20.values[i]),
                fmt(ema12.values[i]),
                fmt(macd[0].values[i]), fmt(macd[1].values[i]), fmt(macd[2].values[i]),
                fmt(rsi14.values[i]),
                fmt(boll[0].values[i]), fmt(boll[1].values[i]), fmt(boll[2].values[i]),
                fmt(kdj[0].values[i]), fmt(kdj[1].values[i]), fmt(kdj[2].values[i])
            ]
            print(cells.joined(separator: " "))
        }

        // 末值非 nil 验收
        print("─────────────────────────────────────────────")
        let endChecks: [(String, Decimal?)] = [
            ("MA20",    ma20.values.last ?? nil),
            ("EMA12",   ema12.values.last ?? nil),
            ("MACD-DIF", macd[0].values.last ?? nil),
            ("MACD-DEA", macd[1].values.last ?? nil),
            ("MACD-MACD", macd[2].values.last ?? nil),
            ("RSI14",   rsi14.values.last ?? nil),
            ("BOLL-M",  boll[0].values.last ?? nil),
            ("BOLL-U",  boll[1].values.last ?? nil),
            ("BOLL-L",  boll[2].values.last ?? nil),
            ("KDJ-K",   kdj[0].values.last ?? nil),
            ("KDJ-D",   kdj[1].values.last ?? nil),
            ("KDJ-J",   kdj[2].values.last ?? nil)
        ]
        let validCount = endChecks.filter { $0.1 != nil }.count
        let total = endChecks.count
        print("末值非 nil 校验：\(validCount) / \(total)")
        for (name, value) in endChecks {
            let status = value != nil ? "✅" : "❌"
            print("  \(status) \(name) = \(fmt(value))")
        }
        print("─────────────────────────────────────────────")
        if validCount == total {
            print("🎉 全部 \(total) 个指标末值非 nil · WP-41 真数据冒烟通过")
        } else {
            print("⚠️  \(total - validCount) 个指标末值为 nil（数据不足？）")
        }
    }

    /// 8 字符宽度的数值格式化（Decimal? → string）
    static func fmt(_ value: Decimal?) -> String {
        guard let v = value else { return "    nil ".padding(toLength: 8, withPad: " ", startingAt: 0) }
        return fmt(v)
    }

    static func fmt(_ value: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2
        nf.minimumIntegerDigits = 1
        let str = nf.string(from: value as NSDecimalNumber) ?? "?"
        return str.padding(toLength: 8, withPad: " ", startingAt: 0)
    }
}
