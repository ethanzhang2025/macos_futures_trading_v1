// 文华财经交割单 CSV 真实样本解析 demo（第 13 个真数据 demo）
//
// 用途：
// - 验证 DealCSVParser 在真实文华 5.0 格式样本下工作（中文表头 + 中文 direction/offsetFlag）
// - 演示 P3 文华迁移用户首要问题："我能把文华历史交易导进来吗？"
// - 完整数据通路：CSV string → RawDeal → Trade → ClosedPosition + 报表
// - 演示 A09 禁做项 ① 落实：RawDeal.toTrade() 显式转换边界（不直接当 Trade 用）
//
// 拓扑（5 段）：
//   段 1 · 嵌入文华 5.0 格式 CSV 字符串（5 笔成交 · 2 段闭合 + 1 笔未平仓）
//   段 2 · DealCSVParser.parse(.wenhua) → [RawDeal]
//   段 3 · RawDeal.toTrade() 显式转换边界 → [Trade]（A09 禁做项 ① 落实）
//   段 4 · PositionMatcher.match + ReviewAnalytics 关键聚合
//   段 5 · 负向场景（缺列 / 非法 direction 值 · DealCSVError 显式可感知）
//
// 运行：swift run WenhuaCSVImportDemo
// 注意：纯本地 CSV 字符串解析，不依赖 Sina 网络

import Foundation
import Shared
import JournalCore

@main
struct WenhuaCSVImportDemo {

    static func main() async throws {
        printSection("文华交割单 CSV 真实样本解析（第 13 个真数据 demo）")

        // 段 1：嵌入文华 5.0 格式 CSV
        printSection("段 1 · 文华 5.0 格式 CSV 样本（5 笔成交）")
        let wenhuaCSV = """
        合约,买卖,开平,成交价,成交量,手续费,成交时间,成交编号
        RB2510,买,开仓,3100,2,4.50,2026-04-23 09:30:15,WH00001
        RB2510,卖,平仓,3180,2,4.50,2026-04-25 14:00:30,WH00002
        IF2506,卖,开仓,4220,1,2.30,2026-04-24 10:15:45,WH00003
        IF2506,买,平仓,4150,1,2.30,2026-04-26 22:30:00,WH00004
        AU2510,买,开仓,1041,3,6.80,2026-04-25 09:00:00,WH00005
        """
        for line in wenhuaCSV.split(separator: "\n") {
            print("  📄 \(line)")
        }

        // 段 2：DealCSVParser.parse → [RawDeal]
        printSection("段 2 · DealCSVParser.parse(.wenhua) → [RawDeal]")
        let rawDeals = try DealCSVParser.parse(wenhuaCSV, format: .wenhua)
        print("  ✅ 解析得 \(rawDeals.count) 条 RawDeal（CSV 行 1:1 映射 · 全 String 字段）")
        for raw in rawDeals.prefix(2) {
            print("     [\(raw.lineNumber)] 合约=\(raw.fields["合约"] ?? "?") · 买卖=\(raw.fields["买卖"] ?? "?") · 开平=\(raw.fields["开平"] ?? "?")")
        }

        // 段 3：RawDeal.toTrade → [Trade]（显式转换边界）
        printSection("段 3 · RawDeal.toTrade() 显式转换边界（A09 禁做项 ① 落实）")
        let trades = try rawDeals.map { try $0.toTrade() }
        print("  ✅ 转换得 \(trades.count) 笔 Trade（中文「买」→ Direction.buy / 「开仓」→ OffsetFlag.open）")
        print("  💡 source=.wenhua 标记数据来源；不允许 Trade 反向修改 RawDeal（单向）")
        print("\n  [Trade 列表]")
        print("    合约     方向  开平  价格      量   手续费  时间")
        for t in trades {
            let dir = t.direction == .buy ? "买" : "卖"
            let off = t.offsetFlag == .open ? "开" : "平"
            print(String(format: "    %@  %@    %@    %@   ×%d   %@   %@",
                         t.instrumentID.padding(toLength: 7, withPad: " ", startingAt: 0),
                         dir, off, fmt(t.price),
                         t.volume,
                         fmt(t.commission),
                         formatTime(t.timestamp)))
        }

        // 段 4：PositionMatcher + Analytics
        printSection("段 4 · PositionMatcher.match + ReviewAnalytics 报表")
        let multipliers: [String: Int] = ["RB2510": 10, "IF2506": 300, "AU2510": 1000]
        let result = PositionMatcher.match(trades: trades, multipliers: multipliers)
        let closed = result.closed
        print("  FIFO 配对：闭合 \(closed.count) 笔 / 未平仓 \(result.openRemaining.count) 组")

        print("\n  [闭合持仓]")
        print("    合约     方向  开仓价   平仓价   量   持仓时长    盈亏")
        for pos in closed {
            let dir = pos.side == .long ? "多" : "空"
            let hours = Int(pos.holdingSeconds / 3600)
            let pnlSign = pos.realizedPnL >= 0 ? "+" : ""
            print(String(format: "    %@  %@    %@   →  %@   ×%d   %3dh    %@%@",
                         pos.instrumentID.padding(toLength: 7, withPad: " ", startingAt: 0),
                         dir, fmt(pos.openPrice), fmt(pos.closePrice), pos.volume, hours,
                         pnlSign, fmt(pos.realizedPnL)))
        }

        let monthly = ReviewAnalytics.monthlyPnL(from: closed)
        let ratio = ReviewAnalytics.profitLossRatio(from: closed)
        let matrix = ReviewAnalytics.instrumentMatrix(from: closed)
        print("\n  [关键聚合]")
        print("    monthlyPnL · 总盈亏 \(fmt(monthly.totalPnL))")
        print("    profitLossRatio · 平盈 \(fmt(ratio.averageWin)) × \(ratio.winCount) / 平亏 \(fmt(ratio.averageLoss)) × \(ratio.lossCount) / 比 \(fmt(ratio.ratio))")
        print("    instrumentMatrix · \(matrix.cells.count) 个合约：")
        for cell in matrix.cells {
            print("      - \(cell.instrumentID): 笔数=\(cell.tradeCount) 总盈亏=\(fmt(cell.totalPnL)) 胜=\(cell.winCount)")
        }

        // 段 5：负向场景
        printSection("段 5 · 负向场景 · DealCSVError 显式可感知")

        // 5.1 缺必填列
        let missingColumnCSV = """
        合约,买卖,成交价,成交量,手续费,成交时间,成交编号
        RB2510,买,3100,2,4.50,2026-04-23 09:30:15,WH00001
        """
        // 5.2 非法 direction 值
        let badDirectionCSV = """
        合约,买卖,开平,成交价,成交量,手续费,成交时间,成交编号
        RB2510,购买,开仓,3100,2,4.50,2026-04-23 09:30:15,WH00001
        """
        // 5.3 非法价格（数值）
        let badPriceCSV = """
        合约,买卖,开平,成交价,成交量,手续费,成交时间,成交编号
        RB2510,买,开仓,not-a-number,2,4.50,2026-04-23 09:30:15,WH00001
        """

        let cases: [(label: String, work: () throws -> Void)] = [
            ("缺『开平』列", {
                _ = try DealCSVParser.parse(missingColumnCSV, format: .wenhua)
            }),
            ("非法 direction `购买`", {
                let raws = try DealCSVParser.parse(badDirectionCSV, format: .wenhua)
                _ = try raws[0].toTrade()
            }),
            ("非法成交价 `not-a-number`", {
                let raws = try DealCSVParser.parse(badPriceCSV, format: .wenhua)
                _ = try raws[0].toTrade()
            }),
        ]
        for c in cases {
            print("  \(errorCase(label: c.label, c.work))")
        }

        // 总结
        // matrix.cells 仅含闭合合约（RB + IF · AU 未平不计入）
        let allOK = trades.count == 5 &&
                     closed.count == 2 &&
                     result.openRemaining.count == 1 &&
                     matrix.cells.count == 2
        printSection(allOK
            ? "🎉 第 13 个真数据 demo 通过（文华 CSV → RawDeal → Trade → 报表完整链路）"
            : "⚠️  数据流验收未达标（详见上方）")
    }

    // MARK: - 错误捕获 helper

    static func errorCase(label: String, _ work: () throws -> Void) -> String {
        do {
            try work()
            return "❌ \(label) → 期望抛错，实际成功"
        } catch let error as DealCSVError {
            return "✅ \(label) → DealCSVError.\(describe(error))"
        } catch {
            return "❌ \(label) → 抛了非预期错：\(error)"
        }
    }

    static func describe(_ e: DealCSVError) -> String {
        switch e {
        case .invalidEncoding: return "invalidEncoding"
        case .missingColumn(let name, let line): return "missingColumn(name=\(name), line=\(line))"
        case .invalidValue(let field, let value, let line): return "invalidValue(field=\(field), value=\(value), line=\(line))"
        case .unsupportedFormat(let f): return "unsupportedFormat(\(f))"
        }
    }

    // MARK: - 通用 helpers

    static func fmt(_ value: Decimal) -> String {
        priceFormatter.string(from: value as NSDecimalNumber) ?? "?"
    }

    static func formatTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
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

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f
    }()
}
