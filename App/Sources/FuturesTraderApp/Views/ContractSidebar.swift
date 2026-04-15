import SwiftUI
import MarketData

struct ContractSidebar: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var searchText = ""

    private var filteredContracts: [(symbol: String, name: String, pinyin: String)] {
        if searchText.isEmpty { return vm.watchList }
        let upper = searchText.uppercased()
        return vm.watchList.filter {
            $0.symbol.uppercased().contains(upper) ||
            $0.name.contains(searchText) ||
            $0.pinyin.contains(upper)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text("合约列表")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Text("\(filteredContracts.count)个")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // 搜索框
            TextField("搜索代码/拼音/中文", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            Divider().background(Theme.border)

            // 行情状态
            if vm.quotes.isEmpty {
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("非交易时段")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textMuted)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
            }

            // 合约列表
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredContracts, id: \.symbol) { item in
                        ContractRow(
                            item: item,
                            quote: vm.quotes.first { $0.symbol == item.symbol },
                            isSelected: vm.selectedSymbol == item.symbol
                        )
                        .onTapGesture { vm.selectSymbol(item.symbol) }
                    }
                }
            }
        }
        .background(Theme.panelBackground)
    }
}

struct ContractRow: View {
    let item: (symbol: String, name: String, pinyin: String)
    let quote: SinaQuote?
    let isSelected: Bool

    var body: some View {
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
            if let q = quote, q.lastPrice > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatPrice(q.lastPrice))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(q.isUp ? Theme.up : Theme.down)
                    Text(formatPercent(q.changePercent))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(q.isUp ? Theme.up : Theme.down)
                }
            } else {
                Text("--")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Theme.selected : Color.clear)
    }

    private func formatPrice(_ p: Decimal) -> String {
        let d = NSDecimalNumber(decimal: p).doubleValue
        if d >= 1000 { return String(format: "%.0f", d) }
        if d >= 10 { return String(format: "%.1f", d) }
        return String(format: "%.2f", d)
    }

    private func formatPercent(_ p: Decimal) -> String {
        let d = NSDecimalNumber(decimal: p).doubleValue
        return String(format: "%+.2f%%", d)
    }
}
