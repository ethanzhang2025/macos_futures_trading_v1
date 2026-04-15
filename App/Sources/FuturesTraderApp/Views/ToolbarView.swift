import SwiftUI

struct ToolbarView: View {
    @EnvironmentObject var vm: AppViewModel

    private let periods = ["日线", "60分", "15分", "5分"]

    var body: some View {
        HStack(spacing: 12) {
            // 合约信息
            Text(vm.selectedName)
                .font(.system(size: 15, weight: .bold))
            Text(vm.selectedSymbol)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.secondary)

            Divider().frame(height: 16)

            // 周期选择
            ForEach(periods, id: \.self) { period in
                Button(action: { vm.selectPeriod(period) }) {
                    Text(period)
                        .font(.system(size: 12, weight: vm.selectedPeriod == period ? .bold : .regular))
                        .foregroundColor(vm.selectedPeriod == period ? .accentColor : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            vm.selectedPeriod == period
                                ? Color.accentColor.opacity(0.1)
                                : Color.clear
                        )
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // 连接状态
            HStack(spacing: 4) {
                Circle()
                    .fill(vm.errorMessage == nil ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(vm.errorMessage == nil ? "已连接" : "断开")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))

        Divider()
    }
}
