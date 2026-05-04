// MainApp · 指标参数编辑 Sheet（v15.2 · 自定义 MA/BOLL/MACD/KDJ/RSI 周期 · v15.11/v15.13 扩 CCI/WR/DMI/STOCH/ROC/BIAS 共 9 Section）
//
// 设计要点：
// - 一个 Sheet 编辑全部 9 类参数（用户一次改完所有偏好 · 不分散到 9 个独立窗口）
// - 草稿模式：取消放弃 · 保存写回 @Binding · 父级 onChange 触发持久化 + 重算
// - 默认还原按钮 · 一键回到 [5,20,60] / [12,26,9] 等出厂值
// - 范围校验：周期 1~500 · BOLL 倍数 1~5 · 不允许负值
// - v15.15 polish：Form 包 ScrollView · 9 Section 高度自适应 · 13" Mac 屏 (~800pt 高) 可正常使用
//
// 不做：
// - 不让用户改 MA 条数（固定 3 条 · 简化数据流）
// - 不按合约/周期隔离参数（全局共享 · 用户期望"我的偏好跨合约一致"）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Shared

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

            // v15.15 polish：9 Section 在 13" Mac 屏（~800pt 高）超出 · 包 ScrollView 可滚动 · sheet 整体高度收 720
            ScrollView {
            Form {
                paramSection("主图均线 MA · 3 条", subtitle: "默认 5 / 20 / 60") {
                    paramField("MA1", maPeriodBinding(0))
                    paramField("MA2", maPeriodBinding(1), leadingPad: true)
                    paramField("MA3", maPeriodBinding(2), leadingPad: true)
                }

                paramSection("主图布林带 BOLL", subtitle: "默认 20 / 2") {
                    paramField("周期", bollParamBinding(0))
                    paramField("倍数", bollParamBinding(1), leadingPad: true)
                }

                paramSection("副图 MACD", subtitle: "默认 12 / 26 / 9（fast 必须 < slow）") {
                    paramField("快线", macdParamBinding(0))
                    paramField("慢线", macdParamBinding(1), leadingPad: true)
                    paramField("信号", macdParamBinding(2), leadingPad: true)
                }

                paramSection("副图 KDJ", subtitle: "默认 9 / 3 / 3") {
                    paramField("周期", kdjParamBinding(0))
                    paramField("smoothK", kdjParamBinding(1), leadingPad: true)
                    paramField("smoothD", kdjParamBinding(2), leadingPad: true)
                }

                paramSection("副图 RSI", subtitle: "默认 14（超买 70 / 超卖 30 阈值固定）") {
                    paramField("周期", $draft.rsiPeriod)
                }

                // v15.11 WP-41 v4 副图扩 4 类（OBV / CCI / WR / 持仓量）· OBV / 持仓量无参数
                paramSection("副图 CCI（顺势指标）", subtitle: "默认 14（>+100 超买 / <-100 超卖 阈值固定）") {
                    paramField("周期", $draft.cciPeriod)
                }

                paramSection("副图 WR（威廉指标）", subtitle: "默认 14（值域 -100~0 · >-20 超买 / <-80 超卖）") {
                    paramField("周期", $draft.wrPeriod)
                }

                // v15.13 副图扩第二批（DMI / Stochastic / ROC / BIAS）
                paramSection("副图 DMI（趋向指标）", subtitle: "默认 14（输出 +DI/-DI 双线 · +DI 红强势 / -DI 绿弱势）") {
                    paramField("周期", $draft.dmiPeriod)
                }

                paramSection("副图 STOCH（随机指标）", subtitle: "默认 14 / 3（%K/%D 双线 · 固定 0~100 视野 · 80/50/20 参考）") {
                    paramField("周期", stochParamBinding(0))
                    paramField("smooth", stochParamBinding(1), leadingPad: true)
                }

                paramSection("副图 ROC（变动率 %）", subtitle: "默认 12（单线 · 上下对称视野 · 0 参考）") {
                    paramField("周期", $draft.rocPeriod)
                }

                paramSection("副图 BIAS（乖离率 %）", subtitle: "默认 6（单线 · 上下对称视野 · 0 参考 · 价格偏离 N 期均线百分比）") {
                    paramField("周期", $draft.biasPeriod)
                }

                // v15.18 第三批副图（Aroon / STC / ElderRay / Choppiness / ForceIndex）
                paramSection("副图 AROON（趋势强度）", subtitle: "默认 14（Up/Down 双线 · 0~100 视野 · 50 参考线）") {
                    paramField("周期", $draft.aroonPeriod)
                }

                paramSection("副图 STC（Schaff Trend Cycle）", subtitle: "默认 23 / 50 / 10 / 10（5 步复合 · 0~100 视野 · 25/75 阈值）") {
                    paramField("快线", stcParamBinding(0))
                    paramField("慢线", stcParamBinding(1), leadingPad: true)
                    paramField("周期", stcParamBinding(2), leadingPad: true)
                    paramField("smooth", stcParamBinding(3), leadingPad: true)
                }

                paramSection("副图 ELDER RAY（多空力量）", subtitle: "默认 13（Bull/Bear 双线 · 0 参考 · 上下对称视野）") {
                    paramField("周期", $draft.elderRayPeriod)
                }

                paramSection("副图 CHOPPINESS（震荡度）", subtitle: "默认 14（单线 · 0~100 视野 · 61.8/38.2 黄金分割 · 高=震荡 / 低=趋势）") {
                    paramField("周期", $draft.choppinessPeriod)
                }

                paramSection("副图 FORCE INDEX（价量复合）", subtitle: "默认 13（单线 · 上下对称视野 · 0 参考 · Alexander Elder）") {
                    paramField("周期", $draft.forceIndexPeriod)
                }

                // v15.18+ batch13 波动率指标（BBW + ATRP）
                paramSection("副图 BBW（布林带宽 %）", subtitle: "默认 20 / 2（与 BOLL 一致 · BBW 极低 = squeeze 即将爆发）") {
                    paramField("周期", bbwParamBinding(0))
                    paramField("倍数", bbwParamBinding(1), leadingPad: true)
                }

                paramSection("副图 ATRP（标准化 ATR%）", subtitle: "默认 14（单线 % · 跨品种波动率比较 · ATR / Close × 100）") {
                    paramField("周期", $draft.atrpPeriod)
                }

                paramSection("主图 Swing 标注（v15.20 batch82 · ⌘⇧W）", subtitle: "lookback 默认 5（前后窗口）· minSpacing 默认 0（同向密集合并 · 0=不过滤）") {
                    paramField("lookback", $draft.swingLookback)
                    paramField("minSpacing", $draft.swingMinSpacing, leadingPad: true)
                }
            }
            .formStyle(.grouped)
            } // ScrollView 结束

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
        .frame(width: 540, height: 720)
    }

    // MARK: - v15.20 batch64 · paramSection / paramField helper（22 Section 模板化 · ~110 行重复 → 1 helper）

    /// 标准参数 Section · Section 标题 + HStack 字段 + 副本说明文字
    @ViewBuilder
    private func paramSection<Fields: View>(
        _ title: String,
        subtitle: String,
        @ViewBuilder fields: () -> Fields
    ) -> some View {
        Section(title) {
            HStack { fields() }
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// 单参数字段（Label + 数字 TextField · 60pt 宽 · 非首字段加 leading pad）
    @ViewBuilder
    private func paramField(_ label: String, _ binding: Binding<Int>, leadingPad: Bool = false) -> some View {
        Text(label).padding(.leading, leadingPad ? 12 : 0)
        TextField("", value: binding, format: .number).frame(width: 60)
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
    private func stochParamBinding(_ i: Int) -> Binding<Int> { arrayBinding(\.stochParams, i) }
    private func stcParamBinding(_ i: Int) -> Binding<Int> { arrayBinding(\.stcParams, i) }
    private func bbwParamBinding(_ i: Int) -> Binding<Int> { arrayBinding(\.bbwParams, i) }

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
        guard b.cciPeriod >= 2 && b.cciPeriod <= 200 else { return false }
        guard b.wrPeriod >= 2 && b.wrPeriod <= 200 else { return false }
        guard b.dmiPeriod >= 2 && b.dmiPeriod <= 200 else { return false }
        guard b.stochParams.count == 2,
              b.stochParams.allSatisfy({ $0 >= 1 && $0 <= 200 }) else { return false }
        guard b.rocPeriod >= 1 && b.rocPeriod <= 200 else { return false }
        guard b.biasPeriod >= 1 && b.biasPeriod <= 200 else { return false }
        // v15.18+ 7 新指标参数范围（合理区间 · 防用户输入越界值）
        guard b.aroonPeriod >= 2 && b.aroonPeriod <= 200 else { return false }
        guard b.stcParams.count == 4,
              b.stcParams.allSatisfy({ $0 >= 1 && $0 <= 200 }) else { return false }
        guard b.elderRayPeriod >= 2 && b.elderRayPeriod <= 200 else { return false }
        guard b.choppinessPeriod >= 2 && b.choppinessPeriod <= 200 else { return false }
        guard b.forceIndexPeriod >= 1 && b.forceIndexPeriod <= 200 else { return false }
        guard b.bbwParams.count == 2,
              b.bbwParams[0] >= 2 && b.bbwParams[0] <= 200,
              b.bbwParams[1] >= 1 && b.bbwParams[1] <= 5 else { return false }
        guard b.atrpPeriod >= 1 && b.atrpPeriod <= 500 else { return false }
        // v15.20 batch85 · Swing lookback 范围（1~50 · 太大遮蔽全局趋势）
        guard b.swingLookback >= 1 && b.swingLookback <= 50 else { return false }
        // v15.21 batch106 · Swing minSpacing 范围（0~100 · 0=不过滤 · 默认 0）
        guard b.swingMinSpacing >= 0 && b.swingMinSpacing <= 100 else { return false }
        return true
    }
}

#endif
