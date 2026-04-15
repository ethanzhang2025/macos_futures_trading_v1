import SwiftUI
import MarketData

struct OrderBookPanel: View {
    let quote: SinaQuote

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            Text("盘口信息")
                .font(.headline)
                .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    // 最新价
                    priceSection

                    Divider()

                    // 买卖盘
                    orderSection

                    Divider()

                    // 行情数据
                    dataSection
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - 最新价区域

    private var priceSection: some View {
        VStack(spacing: 4) {
            Text(formatPrice(quote.lastPrice))
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(quote.isUp ? .red : .green)
            HStack(spacing: 8) {
                Text(formatChange(quote.change))
                    .font(.system(size: 14, design: .monospaced))
                Text(formatPercent(quote.changePercent))
                    .font(.system(size: 14, design: .monospaced))
            }
            .foregroundColor(quote.isUp ? .red : .green)
        }
    }

    // MARK: - 买卖盘

    private var orderSection: some View {
        VStack(spacing: 6) {
            // 卖
            HStack {
                Text("卖一").font(.system(size: 12)).foregroundColor(.secondary)
                Spacer()
                Text(formatPrice(quote.askPrice))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.green)
                Text("\(quote.askVolume)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }

            Divider()

            // 买
            HStack {
                Text("买一").font(.system(size: 12)).foregroundColor(.secondary)
                Spacer()
                Text(formatPrice(quote.bidPrice))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.red)
                Text("\(quote.bidVolume)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }

    // MARK: - 行情数据

    private var dataSection: some View {
        VStack(spacing: 6) {
            dataRow("开盘", formatPrice(quote.open))
            dataRow("最高", formatPrice(quote.high), color: .red)
            dataRow("最低", formatPrice(quote.low), color: .green)
            dataRow("昨收", formatPrice(quote.close))
            dataRow("昨结算", formatPrice(quote.preSettlement))
            dataRow("结算价", formatPrice(quote.settlementPrice))

            Divider()

            dataRow("成交量", formatVolume(quote.volume))
            dataRow("持仓量", formatVolume(quote.openInterest))
        }
    }

    private func dataRow(_ title: String, _ value: String, color: Color = .primary) -> some View {
        HStack {
            Text(title).font(.system(size: 12)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 12, design: .monospaced)).foregroundColor(color)
        }
    }

    // MARK: - Formatting

    private func formatPrice(_ p: Decimal) -> String {
        let d = NSDecimalNumber(decimal: p).doubleValue
        if d >= 1000 { return String(format: "%.0f", d) }
        if d >= 10 { return String(format: "%.1f", d) }
        return String(format: "%.2f", d)
    }

    private func formatChange(_ c: Decimal) -> String {
        let d = NSDecimalNumber(decimal: c).doubleValue
        return String(format: "%+.0f", d)
    }

    private func formatPercent(_ p: Decimal) -> String {
        let d = NSDecimalNumber(decimal: p).doubleValue
        return String(format: "%+.2f%%", d)
    }

    private func formatVolume(_ v: Int) -> String {
        if v >= 10000 { return String(format: "%.1f万", Double(v) / 10000) }
        return "\(v)"
    }
}
