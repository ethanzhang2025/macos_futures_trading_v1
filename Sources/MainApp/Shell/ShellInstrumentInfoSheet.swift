// MainApp · Shell · v17.57 · F10 合约资料 sheet
//
// 设计要点：
// - 显示当前 active workspace 第一 Pane（或 maximized）的合约基础信息
// - v1 占位 · 字段从 PaneConfig.symbol + 简单查表
// - v2 接 InstrumentDashboardWindow 详情链路 · 跨 module Pane 嵌入

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

struct ShellInstrumentInfoSheet: View {

    @EnvironmentObject var shellVM: ShellViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("📋 合约资料 · F10")
                    .font(.headline)
                Spacer()
                Button("关闭") { isPresented = false }
                    .keyboardShortcut(.escape, modifiers: [])
            }

            Divider()

            if let symbol = activeSymbol {
                VStack(alignment: .leading, spacing: 8) {
                    row("合约代码", symbol)
                    row("品种", productName(for: symbol))
                    row("交易所", exchange(for: symbol))
                    row("合约单位", contractUnit(for: symbol))
                    row("最小变动价位", "0.5（占位）")
                    row("保证金率", "10%（占位）")
                    row("手续费", "¥3.5/手（占位）")
                }
                .font(.system(size: 13, design: .monospaced))
            } else {
                Text("当前无 active Pane 或未绑定合约")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
            }

            Divider()

            Text("v1 占位 · v2 接 InstrumentDashboardWindow 真实数据（合约规则 / 历史波动 / 主力换月）")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 420, height: 360)
    }

    private var activeSymbol: String? {
        guard let ws = shellVM.activeWorkspace else { return nil }
        let pane: PaneConfig?
        if let mid = shellVM.maximizedPaneID {
            pane = ws.panes.first { $0.id == mid }
        } else {
            pane = ws.panes.first
        }
        return pane.flatMap { shellVM.effectiveSymbol(for: $0) ?? $0.symbol }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 96, alignment: .leading)
                .foregroundColor(.secondary)
            Text(value)
            Spacer()
        }
    }

    private func productName(for symbol: String) -> String {
        let prefix = symbol.prefix { $0.isLetter }.lowercased()
        switch prefix {
        case "rb": return "螺纹钢"
        case "hc": return "热卷"
        case "i":  return "铁矿石"
        case "j":  return "焦炭"
        case "jm": return "焦煤"
        case "if": return "沪深 300 股指"
        case "ic": return "中证 500 股指"
        case "ih": return "上证 50 股指"
        case "ag": return "白银"
        case "au": return "黄金"
        case "cu": return "铜"
        case "al": return "铝"
        case "ma": return "甲醇"
        case "ta": return "PTA"
        case "sc": return "原油"
        default:   return "(待补)"
        }
    }

    private func exchange(for symbol: String) -> String {
        let prefix = symbol.prefix { $0.isLetter }.lowercased()
        switch prefix {
        case "if", "ic", "ih": return "中金所 CFFEX"
        case "rb", "hc", "ag", "au", "cu", "al": return "上期所 SHFE"
        case "i", "j", "jm":   return "大商所 DCE"
        case "ma", "ta":       return "郑商所 ZCE"
        case "sc":             return "上能所 INE"
        default:               return "(待补)"
        }
    }

    private func contractUnit(for symbol: String) -> String {
        let prefix = symbol.prefix { $0.isLetter }.lowercased()
        switch prefix {
        case "rb", "hc": return "10 吨/手"
        case "i":        return "100 吨/手"
        case "j", "jm":  return "60 吨/手"
        case "if", "ic", "ih": return "指数 × ¥300/点 (¥200 ic/ih)"
        case "ag":       return "15 千克/手"
        case "au":       return "1 千克/手"
        case "cu":       return "5 吨/手"
        case "ma":       return "10 吨/手"
        default:         return "(待补)"
        }
    }
}

#endif
