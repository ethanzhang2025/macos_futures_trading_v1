import SwiftUI
import MarketData

struct OrderBookPanel: View {
    let quote: SinaQuote?
    let symbolName: String

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text("盘口信息")
                    .font(.headline)
                Spacer()
                Text(symbolName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
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
            if let q = quote, q.lastPrice > 0 {
                Text(formatPrice(q.lastPrice))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(q.isUp ? .red : .green)
                HStack(spacing: 8) {
                    Text(formatChange(q.change))
                        .font(.system(size: 14, design: .monospaced))
                    Text(formatPercent(q.changePercent))
                        .font(.system(size: 14, design: .monospaced))
                }
                .foregroundColor(q.isUp ? .red : .green)
            } else {
                Text("--")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Text("非交易时段")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 买卖盘

    private var orderSection: some View {
        VStack(spacing: 6) {
            HStack {
                Text("卖一").font(.system(size: 12)).foregroundColor(.secondary)
                Spacer()
                Text(priceText(quote?.askPrice))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.green)
                Text(volumeText(quote?.askVolume))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }

            Divider()

            HStack {
                Text("买一").font(.system(size: 12)).foregroundColor(.secondary)
                Spacer()
                Text(priceText(quote?.bidPrice))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.red)
                Text(volumeText(quote?.bidVolume))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }

    // MARK: - 行情数据

    private var dataSection: some View {
        VStack(spacing: 6) {
            dataRow("开盘", priceText(quote?.open))
            dataRow("最高", priceText(quote?.high), color: .red)
            dataRow("最低", priceText(quote?.low), color: .green)
            dataRow("昨收", priceText(quote?.close))
            dataRow("昨结算", priceText(quote?.preSettlement))
            dataRow("结算价", priceText(quote?.settlementPrice))

            Divider()

            dataRow("成交量", volumeText(quote?.volume))
            dataRow("持仓量", volumeText(quote?.openInterest))
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

    private func priceText(_ p: Decimal?) -> String {
        guard let p, p > 0 else { return "--" }
        return formatPrice(p)
    }

    private func volumeText(_ v: Int?) -> String {
        guard let v, v > 0 else { return "--" }
        return formatVolume(v)
    }

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
