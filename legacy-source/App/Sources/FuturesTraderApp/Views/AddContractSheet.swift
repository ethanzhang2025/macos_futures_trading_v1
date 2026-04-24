import SwiftUI
import MarketData

/// 添加自选合约面板：显示「全部合约池中还未加入自选」的合约，点击「添加」即加入
struct AddContractSheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var available: [WatchItem] {
        let watched = Set(vm.watchList.map { $0.symbol })
        let pool = WatchItem.allContracts.filter { !watched.contains($0.symbol) }
        if search.isEmpty { return pool }
        let upper = search.uppercased()
        return pool.filter {
            $0.symbol.uppercased().contains(upper) ||
            $0.name.contains(search) ||
            $0.pinyin.contains(upper)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("添加自选合约")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().background(Theme.border)

            TextField("搜索代码/拼音/中文", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(available) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Theme.textPrimary)
                                Text(item.symbol)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(Theme.textMuted)
                            }
                            Spacer()
                            Button {
                                vm.addToWatch(item.symbol)
                            } label: {
                                Text("添加")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Theme.textPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Theme.selected)
                                    .cornerRadius(3)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        Divider().background(Theme.border.opacity(0.4))
                    }
                    if available.isEmpty {
                        Text(search.isEmpty ? "全部合约已在自选中" : "没有匹配的合约")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textMuted)
                            .padding(.top, 40)
                    }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 500)
        .background(Theme.panelBackground)
    }
}
