// PeriodPicker_iOS · 多周期切换 + 主图指标 toggle（WP-61 batch005）
//
// 设计：
//   - 横向 chip 风格周期选择器（1m / 5m / 15m / 30m / 1h / 4h / D / W）
//   - 选中态高亮 + tint 主题色
//   - 主图指标 toggle Menu（MA / EMA / BOLL · v1 占位 · 后续接 IndicatorCore）
//
// 触屏特性：
//   - chip min size 44x32（HIG 触控区）
//   - segmentedControl 风格（标准 SwiftUI Segmented Picker 不够触屏友好 · 自绘）

#if canImport(SwiftUI) && os(iOS)

import SwiftUI
import Shared

struct PeriodPicker_iOS: View {

    @Binding var selectedPeriod: KLinePeriod
    @Binding var enabledIndicators: Set<String>

    /// 一线 trader 最常用的 8 个周期（与产品设计书一致）
    static let displayPeriods: [KLinePeriod] = [
        .minute1, .minute5, .minute15, .minute30,
        .hour1, .hour4, .daily, .weekly
    ]

    /// 主图指标白名单（v1 仅 MA / EMA / BOLL）
    static let displayIndicators: [(id: String, name: String)] = [
        ("MA", "MA"),
        ("EMA", "EMA"),
        ("BOLL", "BOLL")
    ]

    var body: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.displayPeriods, id: \.self) { period in
                        periodChip(period)
                    }
                }
            }

            Divider()
                .frame(height: 24)

            indicatorMenu
        }
    }

    private func periodChip(_ period: KLinePeriod) -> some View {
        let isSelected = period == selectedPeriod
        return Button {
            selectedPeriod = period
        } label: {
            Text(periodLabel(period))
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .frame(minWidth: 44, minHeight: 32)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var indicatorMenu: some View {
        Menu {
            ForEach(Self.displayIndicators, id: \.id) { item in
                Button {
                    if enabledIndicators.contains(item.id) {
                        enabledIndicators.remove(item.id)
                    } else {
                        enabledIndicators.insert(item.id)
                    }
                } label: {
                    HStack {
                        Text(item.name)
                        if enabledIndicators.contains(item.id) {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.xaxis")
                Text("指标")
                    .font(.subheadline)
                if !enabledIndicators.isEmpty {
                    Text("(\(enabledIndicators.count))")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .menuStyle(.borderlessButton)
    }

    /// 显示标签 · "1m" / "1h" / "D"
    private func periodLabel(_ p: KLinePeriod) -> String {
        switch p {
        case .second1, .second3, .second5, .second10, .second15, .second30:
            return p.rawValue
        case .minute1: return "1m"
        case .minute3: return "3m"
        case .minute5: return "5m"
        case .minute15: return "15m"
        case .minute30: return "30m"
        case .hour1: return "1H"
        case .hour2: return "2H"
        case .hour4: return "4H"
        case .daily: return "日"
        case .weekly: return "周"
        case .monthly: return "月"
        }
    }
}

#endif
