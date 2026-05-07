// IPadRootView · iPad 主容器 NavigationSplitView 双栏（WP-61 batch002）
//
// 布局：
//   - sidebar：自选分组 + 合约列表（batch003 接入 WatchlistBook 真数据）
//   - detail：图表（batch004 接入 ChartCore Metal）+ 顶部周期切换（batch005）
//
// 选中态：@State selectedInstrumentID 绑定 sidebar 的 selection
// 横/竖屏自适应：NavigationSplitView 自带响应（balanced / detailOnly）

#if canImport(SwiftUI) && os(iOS)

import SwiftUI

struct IPadRootView: View {

    @State private var selectedInstrumentID: String? = nil
    @State private var selectedPeriod: KLinePeriod = .minute1
    @State private var enabledIndicators: Set<String> = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            WatchlistView_iOS(selection: $selectedInstrumentID)
                .navigationTitle("自选")
        } detail: {
            iPadDetailContent(
                instrumentID: selectedInstrumentID,
                period: $selectedPeriod,
                enabledIndicators: $enabledIndicators
            )
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct iPadDetailContent: View {
    let instrumentID: String?
    @Binding var period: KLinePeriod
    @Binding var enabledIndicators: Set<String>

    var body: some View {
        if let id = instrumentID {
            VStack(spacing: 0) {
                // 顶部条：合约 ID + 周期切换 + 指标 toggle
                HStack(spacing: 12) {
                    Text(id.uppercased())
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospaced()
                    Divider().frame(height: 24)
                    PeriodPicker_iOS(
                        selectedPeriod: $period,
                        enabledIndicators: $enabledIndicators
                    )
                }
                .padding()
                .background(Color(uiColor: .secondarySystemBackground))

                ChartView_iOS(instrumentID: id, period: period)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "hand.point.left.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.tint)
                Text("从左侧选择合约")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
        }
    }
}


#endif
