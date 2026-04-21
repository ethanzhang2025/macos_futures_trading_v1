import SwiftUI
import Shared

struct AccountBar: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var flash: Bool = false

    var body: some View {
        let a = vm.trading.account
        let riskRatio = NSDecimalNumber(decimal: a.riskRatio).doubleValue
        let isDanger = riskRatio >= 80

        HStack(spacing: 18) {
            metric("权益", decimal(a.balance), color: Theme.textPrimary)
            metric("可用", decimal(a.available), color: a.available < 0 ? Theme.up : Theme.textPrimary)
            metric("保证金", decimal(a.margin), color: Theme.textPrimary)
            metric("持仓盈亏", decimalSigned(a.positionPnL), color: pnlColor(a.positionPnL))
            metric("平仓盈亏", decimalSigned(a.closePnL), color: pnlColor(a.closePnL))
            metric("手续费", decimal(a.commission), color: Theme.textSecondary)
            Spacer()
            riskIndicator(ratio: riskRatio, danger: isDanger)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.panelBackground)
        .overlay(Rectangle().fill(Theme.border).frame(height: 0.5), alignment: .top)
        .onAppear { if isDanger { startFlashing() } }
        .onChange(of: isDanger) { _, newValue in
            if newValue { startFlashing() } else { flash = false }
        }
    }

    private func metric(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundColor(Theme.textMuted)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
    }

    private func riskIndicator(ratio: Double, danger: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("风险度").font(.system(size: 10)).foregroundColor(Theme.textMuted)
            HStack(spacing: 6) {
                if danger {
                    Text("⚠️").font(.system(size: 11))
                }
                Text(String(format: "%.1f%%", ratio))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(riskColor(ratio))
                    .opacity(danger && flash ? 0.4 : 1.0)
            }
        }
    }

    private func riskColor(_ r: Double) -> Color {
        if r >= 80 { return Theme.up }
        if r >= 50 { return Color.orange }
        return Theme.textPrimary
    }

    private func pnlColor(_ v: Decimal) -> Color {
        if v > 0 { return Theme.up }
        if v < 0 { return Theme.down }
        return Theme.textPrimary
    }

    private func decimal(_ v: Decimal) -> String {
        Formatters.money(v)
    }

    private func decimalSigned(_ v: Decimal) -> String {
        Formatters.signedMoney(v)
    }

    private func startFlashing() {
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            flash.toggle()
        }
    }
}
