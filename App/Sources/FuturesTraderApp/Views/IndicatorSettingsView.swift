import SwiftUI

/// 指标参数设置面板
struct IndicatorSettingsView: View {
    @Binding var params: IndicatorParams
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text("指标参数设置")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.panelBackground)

            Divider().background(Theme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    maSection
                    Divider().background(Theme.border)
                    bollSection
                    Divider().background(Theme.border)
                    macdSection
                    Divider().background(Theme.border)
                    kdjSection
                    Divider().background(Theme.border)
                    rsiSection
                }
                .padding(16)
            }

            Divider().background(Theme.border)

            HStack {
                Button("恢复默认") {
                    params = .default
                }
                .foregroundColor(Theme.textMuted)
                .buttonStyle(.plain)
                .font(.system(size: 12))

                Spacer()

                Button("完成") {
                    params.save()
                    isPresented = false
                }
                .foregroundColor(Theme.ma5)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .bold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.panelBackground)
        }
        .frame(width: 380, height: 520)
        .background(Theme.background)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 20)
    }

    // MARK: - MA

    private var maSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("MA 均线")
            ForEach(0..<4) { i in
                HStack(spacing: 8) {
                    Toggle("", isOn: $params.maEnabled[i])
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .scaleEffect(0.7)

                    Text("MA\(params.maPeriods[i])")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)
                        .frame(width: 60, alignment: .leading)

                    Text("周期:")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textMuted)

                    intField(value: $params.maPeriods[i], min: 1, max: 250, width: 60)
                }
            }
        }
    }

    private var bollSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("BOLL 布林带")
            HStack {
                paramLabel("周期")
                intField(value: $params.bollPeriod, min: 2, max: 100, width: 60)
                Spacer().frame(width: 20)
                paramLabel("倍数")
                doubleField(value: $params.bollMultiplier, min: 0.5, max: 5, width: 60)
            }
        }
    }

    private var macdSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("MACD")
            HStack {
                paramLabel("快线")
                intField(value: $params.macdFast, min: 2, max: 50, width: 50)
                paramLabel("慢线")
                intField(value: $params.macdSlow, min: 2, max: 100, width: 50)
                paramLabel("信号")
                intField(value: $params.macdSignal, min: 2, max: 50, width: 50)
            }
        }
    }

    private var kdjSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("KDJ")
            HStack {
                paramLabel("N")
                intField(value: $params.kdjN, min: 2, max: 50, width: 50)
                paramLabel("M1")
                intField(value: $params.kdjM1, min: 1, max: 20, width: 50)
                paramLabel("M2")
                intField(value: $params.kdjM2, min: 1, max: 20, width: 50)
            }
        }
    }

    private var rsiSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("RSI")
            HStack {
                paramLabel("周期1")
                intField(value: $params.rsiPeriods[0], min: 2, max: 50, width: 50)
                paramLabel("周期2")
                intField(value: $params.rsiPeriods[1], min: 2, max: 100, width: 50)
                paramLabel("周期3")
                intField(value: $params.rsiPeriods[2], min: 2, max: 100, width: 50)
            }
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(Theme.ma5)
    }

    private func paramLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(Theme.textMuted)
    }

    private func intField(value: Binding<Int>, min: Int, max: Int, width: CGFloat) -> some View {
        TextField("", value: value, formatter: IntFormatter(min: min, max: max))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
            .frame(width: width)
    }

    private func doubleField(value: Binding<Double>, min: Double, max: Double, width: CGFloat) -> some View {
        TextField("", value: value, formatter: DoubleFormatter(min: min, max: max))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
            .frame(width: width)
    }
}

class IntFormatter: NumberFormatter, @unchecked Sendable {
    init(min: Int, max: Int) {
        super.init()
        allowsFloats = false
        minimum = NSNumber(value: min)
        maximum = NSNumber(value: max)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class DoubleFormatter: NumberFormatter, @unchecked Sendable {
    init(min: Double, max: Double) {
        super.init()
        allowsFloats = true
        minimumFractionDigits = 1
        maximumFractionDigits = 2
        minimum = NSNumber(value: min)
        maximum = NSNumber(value: max)
    }
    required init?(coder: NSCoder) { fatalError() }
}
