// MainApp · 指标参数编辑 Sheet（v15.2 · 自定义 MA/BOLL/MACD/KDJ/RSI 周期）
//
// 设计要点：
// - 一个 Sheet 编辑全部 5 类参数（用户一次改完所有偏好 · 不分散到 5 个独立窗口）
// - 草稿模式：取消放弃 · 保存写回 @Binding · 父级 onChange 触发持久化 + 重算
// - 默认还原按钮 · 一键回到 [5,20,60] / [12,26,9] 等出厂值
// - 范围校验：周期 1~500 · BOLL 倍数 1~5 · 不允许负值
//
// 不做：
// - 不让用户改 MA 条数（固定 3 条 · 简化数据流）
// - 不按合约/周期隔离参数（全局共享 · 用户期望"我的偏好跨合约一致"）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI

struct IndicatorParamsSheet: View {

    @Binding var book: IndicatorParamsBook
    @Environment(\.dismiss) private var dismiss
    @State private var draft: IndicatorParamsBook

    init(book: Binding<IndicatorParamsBook>) {
        self._book = book
        self._draft = State(initialValue: book.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("指标参数")
                .font(.title2).bold()
                .padding(.bottom, 12)

            Form {
                Section("主图均线 MA · 3 条") {
                    HStack {
                        Text("MA1")
                        TextField("", value: maPeriodBinding(0), format: .number)
                            .frame(width: 60)
                        Text("MA2").padding(.leading, 12)
                        TextField("", value: maPeriodBinding(1), format: .number)
                            .frame(width: 60)
                        Text("MA3").padding(.leading, 12)
                        TextField("", value: maPeriodBinding(2), format: .number)
                            .frame(width: 60)
                    }
                    Text("默认 5 / 20 / 60")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("主图布林带 BOLL") {
                    HStack {
                        Text("周期")
                        TextField("", value: bollParamBinding(0), format: .number)
                            .frame(width: 60)
                        Text("倍数").padding(.leading, 12)
                        TextField("", value: bollParamBinding(1), format: .number)
                            .frame(width: 60)
                    }
                    Text("默认 20 / 2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("副图 MACD") {
                    HStack {
                        Text("快线")
                        TextField("", value: macdParamBinding(0), format: .number)
                            .frame(width: 60)
                        Text("慢线").padding(.leading, 12)
                        TextField("", value: macdParamBinding(1), format: .number)
                            .frame(width: 60)
                        Text("信号").padding(.leading, 12)
                        TextField("", value: macdParamBinding(2), format: .number)
                            .frame(width: 60)
                    }
                    Text("默认 12 / 26 / 9（fast 必须 < slow）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("副图 KDJ") {
                    HStack {
                        Text("周期")
                        TextField("", value: kdjParamBinding(0), format: .number)
                            .frame(width: 60)
                        Text("smoothK").padding(.leading, 12)
                        TextField("", value: kdjParamBinding(1), format: .number)
                            .frame(width: 60)
                        Text("smoothD").padding(.leading, 12)
                        TextField("", value: kdjParamBinding(2), format: .number)
                            .frame(width: 60)
                    }
                    Text("默认 9 / 3 / 3")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("副图 RSI") {
                    HStack {
                        Text("周期")
                        TextField("", value: $draft.rsiPeriod, format: .number)
                            .frame(width: 60)
                    }
                    Text("默认 14（超买 70 / 超卖 30 阈值固定）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("还原默认") { draft = .default }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    book = draft
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid(draft))
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(width: 540, height: 680)
    }

    // MARK: - Binding helper（按 KeyPath 定位 [Int] 数组 + 下标 · 4 类参数共用）

    /// draft 内 [Int] 数组某下标的 Binding · indices 越界时 get 返回 0 · set 静默忽略
    private func arrayBinding(_ keyPath: WritableKeyPath<IndicatorParamsBook, [Int]>, _ i: Int) -> Binding<Int> {
        Binding(
            get: { draft[keyPath: keyPath].indices.contains(i) ? draft[keyPath: keyPath][i] : 0 },
            set: { newValue in
                guard draft[keyPath: keyPath].indices.contains(i) else { return }
                draft[keyPath: keyPath][i] = newValue
            }
        )
    }

    private func maPeriodBinding(_ i: Int) -> Binding<Int> { arrayBinding(\.mainMAPeriods, i) }
    private func bollParamBinding(_ i: Int) -> Binding<Int> { arrayBinding(\.mainBOLLParams, i) }
    private func macdParamBinding(_ i: Int) -> Binding<Int> { arrayBinding(\.macdParams, i) }
    private func kdjParamBinding(_ i: Int) -> Binding<Int> { arrayBinding(\.kdjParams, i) }

    // MARK: - 校验（保存按钮 .disabled(!isValid) · 越界值不会写回 book）

    private func isValid(_ b: IndicatorParamsBook) -> Bool {
        guard b.mainMAPeriods.count == 3, b.mainBOLLParams.count == 2,
              b.macdParams.count == 3, b.kdjParams.count == 3 else { return false }
        guard b.mainMAPeriods.allSatisfy({ $0 >= 1 && $0 <= 500 }) else { return false }
        guard b.mainBOLLParams[0] >= 1 && b.mainBOLLParams[0] <= 500 else { return false }
        guard b.mainBOLLParams[1] >= 1 && b.mainBOLLParams[1] <= 5 else { return false }
        guard b.macdParams[0] >= 1, b.macdParams[1] > b.macdParams[0], b.macdParams[2] >= 1 else { return false }
        guard b.kdjParams.allSatisfy({ $0 >= 1 && $0 <= 200 }) else { return false }
        guard b.rsiPeriod >= 2 && b.rsiPeriod <= 200 else { return false }
        return true
    }
}

#endif
