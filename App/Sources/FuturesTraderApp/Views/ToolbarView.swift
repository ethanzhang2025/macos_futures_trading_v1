import SwiftUI

struct ToolbarView: View {
    @EnvironmentObject var vm: AppViewModel

    private let periods = ["日线", "60分", "15分", "5分"]

    var body: some View {
        HStack(spacing: 12) {
            Text(vm.selectedName)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Text(vm.selectedSymbol)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Theme.textMuted)

            Rectangle().fill(Theme.border).frame(width: 1, height: 14)

            ForEach(periods, id: \.self) { period in
                Button(action: { vm.selectPeriod(period) }) {
                    Text(period)
                        .font(.system(size: 11, weight: vm.selectedPeriod == period ? .bold : .regular))
                        .foregroundColor(vm.selectedPeriod == period ? Theme.ma5 : Theme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            vm.selectedPeriod == period
                                ? Theme.ma5.opacity(0.15)
                                : Color.clear
                        )
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(vm.errorMessage == nil ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(vm.errorMessage == nil ? "已连接" : "断开")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Theme.panelBackground)

        Rectangle().fill(Theme.border).frame(height: 0.5)
    }
}
