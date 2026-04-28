// MainApp · 预警面板 Scene（WP-52 UI · 共 4 commit）
//
// 进度：
//   ✅ 1/4：开窗 + Mock alerts + 列表占位（条件编辑器/历史/通知通道留后续 commit）
//   ⏳ 2/4：条件编辑器 Sheet（添加/编辑 Alert · 6 类 condition 表单）
//   ⏳ 3/4：启停按钮 + 触发历史列表（AlertEvaluator + AlertHistoryStore 接入）
//   ⏳ 4/4：通知通道（系统通知 / 声音 留 Mac 验收）
//
// 留待 M5：StoreManager 注入 AlertEvaluator + 持久化 alerts

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import AlertCore

struct AlertWindow: View {

    @State private var alerts: [Alert] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if alerts.isEmpty {
                ProgressView("加载预警…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                alertsList
            }
            Divider()
            footerHint
        }
        .frame(minWidth: 720, idealWidth: 880, minHeight: 480, idealHeight: 640)
        .task { alerts = MockAlerts.generate() }
    }

    // MARK: - 顶部 stats

    private var header: some View {
        let active = alerts.filter { $0.status == .active }.count
        let triggered = alerts.filter { $0.status == .triggered }.count
        let paused = alerts.filter { $0.status == .paused }.count

        return HStack(spacing: 24) {
            Text("🔔 预警面板").font(.title2).bold()
            Divider().frame(height: 24)
            stat("总数", "\(alerts.count)")
            stat("活跃", "\(active)", color: .green)
            stat("已触发", "\(triggered)", color: .red)
            stat("已暂停", "\(paused)", color: .secondary)
            Spacer()
            Text("v1 mock · 待 M5 接 AlertEvaluator + 持久化")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private func stat(_ label: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 14, design: .monospaced)).foregroundColor(color)
        }
    }

    // MARK: - 列表

    private var alertsList: some View {
        VStack(spacing: 0) {
            // 表头
            HStack(spacing: 8) {
                Text("名称").frame(maxWidth: .infinity, alignment: .leading)
                Text("合约").frame(width: 60, alignment: .leading)
                Text("条件").frame(width: 200, alignment: .leading)
                Text("状态").frame(width: 70, alignment: .center)
                Text("通道").frame(width: 80, alignment: .leading)
                Text("冷却").frame(width: 50, alignment: .trailing)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(alerts) { alert in
                        alertRow(alert)
                        Divider()
                    }
                }
            }
        }
    }

    private func alertRow(_ a: Alert) -> some View {
        HStack(spacing: 8) {
            Text(a.name).frame(maxWidth: .infinity, alignment: .leading)
            Text(a.instrumentID).frame(width: 60, alignment: .leading)
            Text(a.condition.displayDescription).frame(width: 200, alignment: .leading)
                .foregroundColor(.secondary)
            Self.statusBadge(a.status).frame(width: 70, alignment: .center)
            Text(a.channels.map { Self.channelLabel($0) }.sorted().joined(separator: "·"))
                .frame(width: 80, alignment: .leading)
                .foregroundColor(.secondary)
            Text("\(Int(a.cooldownSeconds))s")
                .frame(width: 50, alignment: .trailing)
                .foregroundColor(.secondary)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private static func statusBadge(_ s: AlertStatus) -> some View {
        switch s {
        case .active:
            badge("活跃", color: .green)
        case .triggered:
            badge("已触发", color: .red)
        case .paused:
            badge("暂停", color: .orange)
        case .cancelled:
            badge("已取消", color: .secondary)
        }
    }

    private static func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.8))
            .cornerRadius(3)
    }

    private static func channelLabel(_ k: NotificationChannelKind) -> String {
        switch k {
        case .inApp:        return "内"
        case .systemNotice: return "通"
        case .sound:        return "声"
        case .console:      return "控"
        case .file:         return "文"
        }
    }

    // MARK: - 底部提示

    private var footerHint: some View {
        HStack(spacing: 16) {
            Label("条件编辑器 · 待 commit 2", systemImage: "square.and.pencil")
            Label("触发历史 · 待 commit 3", systemImage: "clock.arrow.circlepath")
            Label("通知通道 · 待 commit 4", systemImage: "bell.badge")
            Spacer()
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 28)
    }
}

// MARK: - AlertCondition UI 描述（仅 MainApp 用 · 不污染 AlertCore）

extension AlertCondition {
    /// 简短中文描述（列表展示用）· 与 toolbar Picker displayName 风格一致
    var displayDescription: String {
        switch self {
        case .priceAbove(let p):           return "价格 > \(formatDecimal(p))"
        case .priceBelow(let p):           return "价格 < \(formatDecimal(p))"
        case .priceCrossAbove(let p):      return "上穿 \(formatDecimal(p))"
        case .priceCrossBelow(let p):      return "下穿 \(formatDecimal(p))"
        case .horizontalLineTouched(_, let p): return "触线 \(formatDecimal(p))"
        case .volumeSpike(let m, let n):
            return "成交量 ≥ \(formatDecimal(m))× / \(n)期"
        case .priceMoveSpike(let p, let s):
            return "急动 ≥ \(formatDecimal(p))% / \(s)秒"
        }
    }

    private func formatDecimal(_ v: Decimal) -> String {
        let n = NSDecimalNumber(decimal: v).doubleValue
        if abs(n - n.rounded()) < 0.01 { return String(format: "%.0f", n) }
        return String(format: "%.2f", n)
    }
}

// MARK: - Mock alerts（v1 演示 · M5 替换为 AlertEvaluator + 持久化 alerts）

enum MockAlerts {

    /// 8 个示例 · 覆盖 6 种 condition + 4 种 status + 多合约
    static func generate() -> [Alert] {
        [
            Alert(name: "螺纹突破 3900",
                  instrumentID: "RB0",
                  condition: .priceAbove(3900)),
            Alert(name: "沪深 300 跌破 3450",
                  instrumentID: "IF0",
                  condition: .priceBelow(3450),
                  cooldownSeconds: 300),
            Alert(name: "黄金上穿 460",
                  instrumentID: "AU0",
                  condition: .priceCrossAbove(460),
                  channels: [.inApp, .systemNotice, .sound]),
            Alert(name: "铜下穿 72000",
                  instrumentID: "CU0",
                  condition: .priceCrossBelow(72000),
                  status: .triggered,
                  lastTriggeredAt: Date().addingTimeInterval(-120)),
            Alert(name: "螺纹成交量异常",
                  instrumentID: "RB0",
                  condition: .volumeSpike(multiple: 3, windowBars: 20),
                  channels: [.inApp]),
            Alert(name: "黄金 60 秒急动 1%",
                  instrumentID: "AU0",
                  condition: .priceMoveSpike(percentThreshold: 1, windowSeconds: 60),
                  status: .paused),
            Alert(name: "RB0 触水平线 3850",
                  instrumentID: "RB0",
                  condition: .horizontalLineTouched(drawingID: UUID(), price: 3850),
                  channels: [.inApp, .systemNotice]),
            Alert(name: "IF0 上穿 3550 月线",
                  instrumentID: "IF0",
                  condition: .priceCrossAbove(3550),
                  status: .cancelled,
                  cooldownSeconds: 0),
        ]
    }
}

#endif
