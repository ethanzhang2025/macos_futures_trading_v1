// QuoteDetailPanel_iOS · 行情 detail 顶部条（WP-61 batch008）
//
// 显示：
//   - 最新价（大字号 · monospaced · 红绿染色）
//   - 涨跌额 + 涨跌%
//   - OHLC（开/高/低/收）
//   - 成交量 / 持仓量（占位 0 · 真实数据接入后非零）
//
// 数据源：
//   - 暂用 ChartView_iOS.demoBars 的最后一根（与图表数据一致）
//   - batch008+ 接实时 Tick 时换 SinaTickSource

#if canImport(SwiftUI) && os(iOS)

import SwiftUI
import Shared

struct QuoteDetailPanel_iOS: View {

    let instrumentID: String
    let period: KLinePeriod

    @State private var currentBar: KLine? = nil
    @State private var prevClose: Double = 0

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if let bar = currentBar {
                priceColumn(bar)
                Divider().frame(height: 36)
                ohlcColumn(bar)
                Divider().frame(height: 36)
                volumeColumn(bar)
            } else {
                Text("--")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemBackground))
        .task(id: "\(instrumentID)-\(period.rawValue)") {
            let bars = ChartView_iOS.demoBars(for: instrumentID, period: period, count: 200)
            if bars.count >= 2 {
                self.currentBar = bars.last
                self.prevClose = NSDecimalNumber(decimal: bars[bars.count - 2].close).doubleValue
            } else {
                self.currentBar = bars.last
                self.prevClose = 0
            }
        }
    }

    // MARK: - 最新价

    private func priceColumn(_ bar: KLine) -> some View {
        let close = NSDecimalNumber(decimal: bar.close).doubleValue
        let delta = close - prevClose
        let pct = prevClose > 0 ? (delta / prevClose) * 100 : 0
        let bullish = delta >= 0
        let color: Color = bullish ? .red : .green

        return VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.2f", close))
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            HStack(spacing: 6) {
                Text(String(format: "%@%.2f", bullish ? "+" : "", delta))
                    .font(.caption)
                    .foregroundStyle(color)
                    .monospacedDigit()
                Text(String(format: "(%@%.2f%%)", bullish ? "+" : "", pct))
                    .font(.caption)
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - OHLC

    private func ohlcColumn(_ bar: KLine) -> some View {
        let openD = NSDecimalNumber(decimal: bar.open).doubleValue
        let highD = NSDecimalNumber(decimal: bar.high).doubleValue
        let lowD = NSDecimalNumber(decimal: bar.low).doubleValue
        let closeD = NSDecimalNumber(decimal: bar.close).doubleValue

        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
            GridRow {
                ohlcCell("开", openD)
                ohlcCell("高", highD, color: .red)
            }
            GridRow {
                ohlcCell("低", lowD, color: .green)
                ohlcCell("收", closeD)
            }
        }
    }

    private func ohlcCell(_ label: String, _ value: Double, color: Color = .primary) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%.2f", value))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    // MARK: - 成交量 / 持仓量

    private func volumeColumn(_ bar: KLine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("成交量")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(bar.volume)")
                    .font(.caption)
                    .monospacedDigit()
            }
            HStack(spacing: 4) {
                Text("持仓量")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(NSDecimalNumber(decimal: bar.openInterest).intValue)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#endif
