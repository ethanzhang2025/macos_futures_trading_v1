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
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Text(symbolName)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().background(Theme.border)

            ScrollView {
                VStack(spacing: 12) {
                    priceSection
                    Divider().background(Theme.border)
                    orderSection
                    Divider().background(Theme.border)
                    dataSection
                }
                .padding(12)
            }
        }
        .background(Theme.panelBackground)
    }

    private var priceSection: some View {
        VStack(spacing: 4) {
            if let q = quote, q.lastPrice > 0 {
                Text(formatPrice(q.lastPrice))
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundColor(q.isUp ? Theme.up : Theme.down)
                HStack(spacing: 8) {
                    Text(formatChange(q.change))
                        .font(.system(size: 13, design: .monospaced))
                    Text(formatPercent(q.changePercent))
                        .font(.system(size: 13, design: .monospaced))
                }
                .foregroundColor(q.isUp ? Theme.up : Theme.down)
            } else {
                Text("--")
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.textMuted)
                Text("非交易时段")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
            }
        }
    }

    private var orderSection: some View {
        VStack(spacing: 6) {
            HStack {
                Text("卖一").font(.system(size: 11)).foregroundColor(Theme.textMuted)
                Spacer()
                Text(priceText(quote?.askPrice))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.down)
                Text(volumeText(quote?.askVolume))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 45, alignment: .trailing)
            }
            Rectangle().fill(Theme.border).frame(height: 0.5)
            HStack {
                Text("买一").font(.system(size: 11)).foregroundColor(Theme.textMuted)
                Spacer()
                Text(priceText(quote?.bidPrice))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.up)
                Text(volumeText(quote?.bidVolume))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 45, alignment: .trailing)
            }
        }
    }

    private var dataSection: some View {
        VStack(spacing: 5) {
            dataRow("开盘", priceText(quote?.open))
            dataRow("最高", priceText(quote?.high), color: Theme.up)
            dataRow("最低", priceText(quote?.low), color: Theme.down)
            dataRow("昨收", priceText(quote?.close))
            dataRow("昨结算", priceText(quote?.preSettlement))
            dataRow("结算价", priceText(quote?.settlementPrice))
            Rectangle().fill(Theme.border).frame(height: 0.5)
            dataRow("成交量", volumeText(quote?.volume))
            dataRow("持仓量", volumeText(quote?.openInterest))
        }
    }

    private func dataRow(_ title: String, _ value: String, color: Color = Theme.textPrimary) -> some View {
        HStack {
            Text(title).font(.system(size: 11)).foregroundColor(Theme.textMuted)
            Spacer()
            Text(value).font(.system(size: 11, design: .monospaced)).foregroundColor(color)
        }
    }

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
