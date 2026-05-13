// v17.171 · 盘中复盘日期选择 sheet（trader 每晚选一天回放）
//
// 流程：
// 1. caller 传入当前 replayAllBars 内所有出现过的"交易日"（startOfDay 列表）
// 2. user 在 list 里挑一天
// 3. onConfirm 触发 · caller 调 enterIntradayReplay(date:)
//
// v1 简单 · v2 可加：
//  · 节假日 / 周末标红
//  · 当日趋势 mini sparkline 预览
//  · 多日批量加载（连续 N 日）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Shared

struct IntradayDatePickerSheet: View {

    let availableDates: [Date]
    let onConfirm: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("盘中复盘 · 选定日期")
                .font(.title2).bold()
            Text("挑一天 · 回放当日完整 K 线（含前 60 根预热让指标有数据）· trader 每晚必复盘")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            if availableDates.isEmpty {
                Spacer()
                Text("当前历史数据里没有可选日期")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(selection: $selectedDate) {
                    ForEach(availableDates.reversed(), id: \.self) { date in
                        Label(dateFormatter.string(from: date), systemImage: "calendar")
                            .tag(date as Date?)
                    }
                }
                .listStyle(.bordered)
                .frame(minWidth: 360, minHeight: 280)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("确认 · 开始复盘") {
                    if let d = selectedDate {
                        onConfirm(d)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedDate == nil)
            }
        }
        .padding(20)
        .frame(width: 460, height: 420)
        .onAppear {
            // 默认选中最新一天（trader 多数情况复盘最近交易日）
            selectedDate = availableDates.last
        }
    }
}

#endif
