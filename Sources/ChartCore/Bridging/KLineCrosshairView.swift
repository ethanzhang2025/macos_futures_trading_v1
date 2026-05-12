// ChartCore · 视觉迭代第 2 项 · 主图十字光标 + OHLC 浮窗
//
// 设计：
// - macOS onContinuousHover 跟踪鼠标 · 不影响 pan/zoom gesture（事件不互斥 · 但 hover 视觉跟随）
// - 反向计算 hover x → bar index · y → 价格 · 用 viewport.startIndex/visibleCount + priceRange 投影
// - 浮窗显示 OHLC + 量 + 当前 y 对应价位 · 接边时翻转防越界
// - 半透明虚线十字 · 不抢主图视觉

#if canImport(SwiftUI)

import SwiftUI
import Foundation
import Shared

public struct KLineCrosshairView: View {

    public let bars: [KLine]
    public let viewport: RenderViewport
    public let priceRange: ClosedRange<Decimal>
    public let period: KLinePeriod
    /// v15.x 主题切换支持 · 默认深色保兼容
    public let tooltipBackground: Color
    public let tooltipPrimaryText: Color
    public let tooltipSecondaryText: Color
    public let crosshairLineColor: Color
    /// v18 · 跨周期十字光标深度集成 · 同 group 兄弟 Pane 广播的时间
    /// nil 时不渲染外部光标 · 非 nil 时画蓝色虚线竖线 + 顶部 🎯 tag（仅时间维度跨周期共振）
    public let externalTime: Date?

    @State private var hoverPoint: CGPoint?

    /// 时间格式按周期动态（v12.11 折衷方案）：
    /// - 1/5/15分：MM-dd HH:mm（跨度 ≤ 4 个月 · 跨年罕见 · 紧凑）
    /// - 30/60分：yy-MM-dd HH:mm（跨度 5-8 个月 · 简化 2 位年区分跨年）
    /// - 日/周：yyyy-MM-dd（日期为主 · 完整年份）
    /// - 月：yyyy-MM
    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        switch period {
        case .daily, .weekly:        f.dateFormat = "yyyy-MM-dd"
        case .monthly:               f.dateFormat = "yyyy-MM"
        case .minute30, .hour1:      f.dateFormat = "yy-MM-dd HH:mm"
        default:                     f.dateFormat = "MM-dd HH:mm"
        }
        return f
    }

    public init(
        bars: [KLine],
        viewport: RenderViewport,
        priceRange: ClosedRange<Decimal>,
        period: KLinePeriod,
        tooltipBackground: Color = Color.black.opacity(0.85),
        tooltipPrimaryText: Color = .white,
        tooltipSecondaryText: Color = Color.white.opacity(0.7),
        crosshairLineColor: Color = Color.white.opacity(0.5),
        externalTime: Date? = nil
    ) {
        self.bars = bars
        self.viewport = viewport
        self.priceRange = priceRange
        self.period = period
        self.tooltipBackground = tooltipBackground
        self.tooltipPrimaryText = tooltipPrimaryText
        self.tooltipSecondaryText = tooltipSecondaryText
        self.crosshairLineColor = crosshairLineColor
        self.externalTime = externalTime
    }

    public var body: some View {
        GeometryReader { geom in
            ZStack {
                // 透明 hover 接收层（不挡 K 线 gesture · 仅接受 hover 事件）
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let pt): hoverPoint = pt
                        case .ended: hoverPoint = nil
                        }
                    }

                // v18 · 外部光标（同 group 兄弟 Pane 广播 · 仅竖线 + 顶部 tag）
                // 画在本地光标下层（zIndex 隐式靠前后顺序）· 本地光标覆盖时视觉优先本地
                if let ext = externalTime, let extX = externalBarX(time: ext, in: geom.size) {
                    externalCrosshairLine(x: extX, in: geom.size)
                    externalTopTag(time: ext, x: extX, in: geom.size)
                }

                if let pt = hoverPoint, let info = computeBarInfo(at: pt, in: geom.size) {
                    crosshairLines(at: pt, in: geom.size)
                    // 视觉迭代第 5 项：右边价格浮标 + 底边时间浮标（贴主图右下边 · 文华标准）
                    rightPriceTag(price: info.cursorPrice, at: pt, in: geom.size)
                    bottomTimeTag(time: info.bar.openTime, at: pt, in: geom.size)
                    OHLCTooltip(
                        time: timeFormatter.string(from: info.bar.openTime),
                        bar: info.bar,
                        cursorPrice: info.cursorPrice,
                        prevClose: info.prevClose,
                        volumeRatio: info.volumeRatio,
                        backgroundColor: tooltipBackground,
                        primaryText: tooltipPrimaryText,
                        secondaryText: tooltipSecondaryText
                    )
                    .position(tooltipPosition(at: pt, in: geom.size))
                }
            }
        }
    }

    // MARK: - 私有

    private struct BarInfo {
        let bar: KLine
        let cursorPrice: Decimal
        /// v15.18 · 前一根 close（用于计算涨跌幅 / 振幅）· 第一根为 nil
        let prevClose: Decimal?
        /// v15.20 batch67 · 量比 = 当根 vol / 前 5 根 vol 平均（trader 看放量/缩量）· 不足 1 根 nil
        let volumeRatio: Double?
    }

    private func computeBarInfo(at pt: CGPoint, in size: CGSize) -> BarInfo? {
        // v15.39 · 复用 ChartHitTester（取代手写 xRatio 计算 · 边界 clamp 与 barCount 校验统一）
        guard let barIndex = ChartHitTester.barIndex(
            atX: pt.x, width: size.width, viewport: viewport, barCount: bars.count
        ) else { return nil }
        let bar = bars[barIndex]
        let prevClose: Decimal? = barIndex > 0 ? bars[barIndex - 1].close : nil
        // v15.20 batch67 · 量比（前 5 根均值 · 不足时退化）
        let priorStart = max(0, barIndex - 5)
        let prior = bars[priorStart..<barIndex]
        let volumeRatio: Double? = {
            guard !prior.isEmpty else { return nil }
            let avg = Double(prior.map(\.volume).reduce(0, +)) / Double(prior.count)
            guard avg > 0 else { return nil }
            return Double(bar.volume) / avg
        }()
        let cursorPrice = ChartHitTester.price(atY: pt.y, height: size.height, priceRange: priceRange)
        return BarInfo(bar: bar, cursorPrice: cursorPrice, prevClose: prevClose, volumeRatio: volumeRatio)
    }

    private func crosshairLines(at pt: CGPoint, in size: CGSize) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: pt.y))
            p.addLine(to: CGPoint(x: size.width, y: pt.y))
            p.move(to: CGPoint(x: pt.x, y: 0))
            p.addLine(to: CGPoint(x: pt.x, y: size.height))
        }
        .stroke(crosshairLineColor, style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
        .allowsHitTesting(false)
    }

    /// 右边价格浮标（贴主图右沿 · 黄底黑字 · 文华标准）
    private func rightPriceTag(price: Decimal, at pt: CGPoint, in size: CGSize) -> some View {
        Text(String(format: "%.2f", NSDecimalNumber(decimal: price).doubleValue))
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.black)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.yellow)
            .cornerRadius(2)
            .position(x: size.width - 28, y: pt.y)
            .allowsHitTesting(false)
    }

    /// 底边时间浮标（贴主图下沿 · 黄底黑字 · 文华标准）
    private func bottomTimeTag(time: Date, at pt: CGPoint, in size: CGSize) -> some View {
        Text(timeFormatter.string(from: time))
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.black)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.yellow)
            .cornerRadius(2)
            .position(x: pt.x, y: size.height - 10)
            .allowsHitTesting(false)
    }

    /// 浮窗位置：默认鼠标右下偏移 · 接边翻转
    /// v15.20 batch67 · width 200→210 / height 130→160（加 量比 + 持仓 两 row）
    private func tooltipPosition(at pt: CGPoint, in size: CGSize) -> CGPoint {
        let tooltipWidth: CGFloat = 210
        let tooltipHeight: CGFloat = 160
        let dx: CGFloat = pt.x + 12 + tooltipWidth / 2 < size.width
            ? tooltipWidth / 2 + 12
            : -tooltipWidth / 2 - 12
        let dy: CGFloat = pt.y + 12 + tooltipHeight / 2 < size.height
            ? tooltipHeight / 2 + 12
            : -tooltipHeight / 2 - 12
        return CGPoint(x: pt.x + dx, y: pt.y + dy)
    }

    // MARK: - v18 · 外部光标（同 group 兄弟广播 · 跨周期共振）

    /// externalTime → 像素 x · 找最后一根 openTime ≤ externalTime 的 bar · 不在 viewport 可视区返 nil
    private func externalBarX(time: Date, in size: CGSize) -> CGFloat? {
        guard !bars.isEmpty,
              let idx = bars.lastIndex(where: { $0.openTime <= time }) else { return nil }
        return ChartHitTester.xPosition(forBarIndex: idx, width: size.width, viewport: viewport)
    }

    /// 外部光标竖线（仅时间维度 · 浅蓝虚线 · 与本地黄白虚线区分）
    private func externalCrosshairLine(x: CGFloat, in size: CGSize) -> some View {
        Path { p in
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: size.height))
        }
        .stroke(Color.cyan.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        .allowsHitTesting(false)
    }

    /// 外部光标顶部 tag（🎯 + 时间 · 提示 trader 这是同组广播来的）
    private func externalTopTag(time: Date, x: CGFloat, in size: CGSize) -> some View {
        Text("🎯 \(timeFormatter.string(from: time))")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.cyan.opacity(0.85))
            .cornerRadius(2)
            .position(x: x, y: 10)
            .allowsHitTesting(false)
    }
}

// MARK: - OHLC 浮窗

private struct OHLCTooltip: View {
    let time: String
    let bar: KLine
    let cursorPrice: Decimal
    /// v15.18 · 前一根 close（计算涨跌幅 / 振幅）· nil 时省略
    let prevClose: Decimal?
    /// v15.20 batch67 · 量比（vs 前 5 根均值）
    let volumeRatio: Double?
    let backgroundColor: Color
    let primaryText: Color
    let secondaryText: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(time)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(secondaryText)
            Divider().background(secondaryText.opacity(0.3))
            row(label: "开", value: bar.open, color: primaryText)
            row(label: "高", value: bar.high, color: .red)
            row(label: "低", value: bar.low, color: .green)
            row(label: "收", value: bar.close, color: bar.close >= bar.open ? .red : .green)
            row(label: "量", value: Decimal(bar.volume), color: secondaryText)
            // v15.20 batch67 · 量比 + 持仓量（trader 看放缩量 / OI 趋势）
            if let ratio = volumeRatio {
                let ratioColor: Color = ratio >= 1.5 ? .red : (ratio < 0.7 ? .green : secondaryText)
                rawTextRow(label: "量比", text: String(format: "%.2f", ratio), color: ratioColor)
            }
            row(label: "持仓", value: bar.openInterest, color: secondaryText)
            // v15.18 · 涨跌幅 / 振幅（trader 实用 · 需 prevClose）
            if let pc = prevClose, pc > 0 {
                Divider().background(secondaryText.opacity(0.3))
                let changePct = (bar.close - pc) / pc * 100
                let amplPct = (bar.high - bar.low) / pc * 100
                let changeColor: Color = bar.close >= pc ? .red : .green
                pctRow(label: "涨跌", value: changePct, color: changeColor)
                pctRow(label: "振幅", value: amplPct, color: .yellow)
            }
            Divider().background(secondaryText.opacity(0.3))
            row(label: "价位", value: cursorPrice, color: .yellow)
        }
        .padding(8)
        .frame(width: 210, alignment: .leading)
        .background(backgroundColor)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(secondaryText.opacity(0.3), lineWidth: 0.5)
        )
        .allowsHitTesting(false)
    }

    private func row(label: String, value: Decimal, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(secondaryText)
                .frame(width: 28, alignment: .leading)
            Text(value.description)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(color)
            Spacer()
        }
    }

    private func pctRow(label: String, value: Decimal, color: Color) -> some View {
        let d = NSDecimalNumber(decimal: value).doubleValue
        let sign = d >= 0 ? "+" : ""
        let text = String(format: "\(sign)%.2f%%", d)
        return rawTextRow(label: label, text: text, color: color)
    }

    /// v15.20 batch67 · 通用文本 row（量比等非 Decimal 数据）
    private func rawTextRow(label: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(secondaryText)
                .frame(width: 28, alignment: .leading)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(color)
            Spacer()
        }
    }
}

#endif
