// v17.151 · 主图叠加参数 sheet（trader 调 SuperTrend / Ichimoku / Donchian / Keltner 4 种 overlay 参数）
// 与 IndicatorParamsSheet（副图参数）完全对称 · 入口 toolbar mainChartOverlayMenu 加 "参数..." 项触发
//
// 参数源：MainChartOverlayBook（v17.139/140/142 加字段 · 与本 sheet 同步）
// 设计：草稿 + 取消/保存 + 还原默认 · 与 IndicatorParamsSheet 同模板
// 校验：period 1~500 · multiplier 1~10（与 IndicatorCore parameters 对齐）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Shared

struct MainChartOverlayParamsSheet: View {

    @Binding var book: MainChartOverlayBook
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MainChartOverlayBook

    init(book: Binding<MainChartOverlayBook>) {
        self._book = book
        self._draft = State(initialValue: book.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("主图叠加参数")
                .font(.title2).bold()
                .padding(.bottom, 4)
            Text("trader 调 7 种主图 overlay 参数（VWAP / Pivot 无参）· SuperTrend / Ichimoku / Donchian / Keltner / SAR / PriceChannel / Envelopes")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 12)

            ScrollView {
                Form {
                    paramSection("SuperTrend（ATR 趋势止损线）", subtitle: "默认 10 / 3 · period=ATR 周期 · mult=带宽倍数（rolling lock · 与麦语言 SUPERTREND 一致）") {
                        paramField("period", $draft.superTrendPeriod)
                        paramFieldDecimal("mult", $draft.superTrendMultiplier, leadingPad: true)
                    }

                    paramSection("Ichimoku（一目均衡表 4 线）", subtitle: "默认 9 / 26 / 52 · Tenkan 转换线 / Kijun 基准线 / Senkou-B 周期（CHIKOU 暂不画）") {
                        paramField("Tenkan", $draft.ichimokuTenkan)
                        paramField("Kijun",  $draft.ichimokuKijun, leadingPad: true)
                        paramField("Senkou", $draft.ichimokuSenkou, leadingPad: true)
                    }

                    paramSection("Donchian Channel（唐奇安通道）", subtitle: "默认 20 · 海龟交易法核心 · HHV/LLV/MID 3 线") {
                        paramField("period", $draft.donchianPeriod)
                    }

                    paramSection("Keltner Channel（肯特纳通道）", subtitle: "默认 20 / 10 / 2 · EMA 中轴周期 / ATR 周期 / multiplier · 趋势 + 挤压识别") {
                        paramField("EMA",  $draft.keltnerEMA)
                        paramField("ATR",  $draft.keltnerATR, leadingPad: true)
                        paramFieldDecimal("mult", $draft.keltnerMultiplier, leadingPad: true)
                    }

                    // v17.153 · 3 个新主图 overlay 参数
                    paramSection("SAR（抛物线转向止损点）", subtitle: "默认 0.02 / 0.2 · step 加速因子初值 / max 上限 · Welles Wilder 经典") {
                        paramFieldDecimal("step", $draft.sarStep)
                        paramFieldDecimal("max",  $draft.sarMax, leadingPad: true)
                    }

                    paramSection("Price Channel（价格通道 close 版）", subtitle: "默认 20 · close 滚动 N 期 HHV/LLV 上下轨（vs Donchian 用 high/low）") {
                        paramField("period", $draft.priceChannelPeriod)
                    }

                    paramSection("Envelopes（包络线）", subtitle: "默认 20 / 2.5% · MA 中轴周期 / 上下偏移百分比 · 经典支撑阻力区") {
                        paramField("period",  $draft.envelopesPeriod)
                        paramFieldDecimal("%", $draft.envelopesPercent, leadingPad: true)
                    }
                }
                .formStyle(.grouped)
            }

            HStack {
                Button("还原默认") { draft = .default }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    book = draft
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid(draft))
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(width: 540, height: 600)
    }

    // MARK: - paramSection / paramField helper（与 IndicatorParamsSheet 同模板）

    @ViewBuilder
    private func paramSection<Fields: View>(
        _ title: String,
        subtitle: String,
        @ViewBuilder fields: () -> Fields
    ) -> some View {
        Section(title) {
            HStack { fields() }
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func paramField(_ label: String, _ binding: Binding<Int>, leadingPad: Bool = false) -> some View {
        Text(label).padding(.leading, leadingPad ? 12 : 0)
        TextField("", value: binding, format: .number).frame(width: 60)
    }

    /// Decimal 字段（SuperTrend / Keltner multiplier · 允许小数 1.0-10.0）
    @ViewBuilder
    private func paramFieldDecimal(_ label: String, _ binding: Binding<Decimal>, leadingPad: Bool = false) -> some View {
        Text(label).padding(.leading, leadingPad ? 12 : 0)
        TextField("", value: binding, format: .number).frame(width: 60)
    }

    // MARK: - 校验（与 IndicatorCore parameters 对齐）

    private func isValid(_ b: MainChartOverlayBook) -> Bool {
        guard b.superTrendPeriod >= 1 && b.superTrendPeriod <= 500 else { return false }
        guard b.superTrendMultiplier >= 1 && b.superTrendMultiplier <= 20 else { return false }
        guard b.ichimokuTenkan >= 1 && b.ichimokuTenkan <= 200 else { return false }
        guard b.ichimokuKijun  >= 1 && b.ichimokuKijun  <= 200 else { return false }
        guard b.ichimokuSenkou >= 1 && b.ichimokuSenkou <= 500 else { return false }
        guard b.donchianPeriod >= 1 && b.donchianPeriod <= 500 else { return false }
        guard b.keltnerEMA >= 1 && b.keltnerEMA <= 500 else { return false }
        guard b.keltnerATR >= 1 && b.keltnerATR <= 500 else { return false }
        guard b.keltnerMultiplier >= 1 && b.keltnerMultiplier <= 10 else { return false }
        // v17.153 · 3 个新参数范围（与 IndicatorCore 对齐）
        guard b.sarStep > 0 && b.sarStep <= 1 else { return false }
        guard b.sarMax  > 0 && b.sarMax  <= 1 else { return false }
        guard b.priceChannelPeriod >= 1 && b.priceChannelPeriod <= 500 else { return false }
        guard b.envelopesPeriod    >= 1 && b.envelopesPeriod    <= 500 else { return false }
        guard b.envelopesPercent   > 0 && b.envelopesPercent   <= 50  else { return false }
        return true
    }
}

#endif
