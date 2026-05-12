// MainApp · 偏好设置 Scene（v15.18 · 通知 tab 真实化 · WP-23 FeatureFlag wire）
//
// v15.18 通知 tab 真实化：用户可开关系统通知 / 声音（重启生效 · 提示横幅）
// 其余 tab 保留占位（图表已有 ⌘⇧D 全局切主题 · 订阅 Stage B WP-91）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Shared

struct SettingsContentView: View {

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("通用", systemImage: "gearshape") }
            NotificationSettingsTab()
                .tabItem { Label("通知", systemImage: "bell.badge") }
            PrivacySettingsTab()
                .tabItem { Label("隐私", systemImage: "hand.raised.fill") }
            ChartSettingsTab()
                .tabItem { Label("图表", systemImage: "chart.line.uptrend.xyaxis") }
            placeholder(title: "数据", note: "行情源 / 缓存路径 / 加密 passphrase（Keychain wire 待 Stage B IAP）")
                .tabItem { Label("数据", systemImage: "externaldrive") }
            placeholder(title: "订阅", note: "Pro / Pro 500 / 设备绑定（待 WP-91 IAP 接入）")
                .tabItem { Label("订阅", systemImage: "person.badge.key") }
        }
        .frame(width: 520, height: 400)
    }

    private func placeholder(title: String, note: String) -> some View {
        VStack(spacing: 12) {
            Text(title).font(.title2)
            Text(note).foregroundColor(.secondary).multilineTextAlignment(.center)
            Text("（待后续 WP 接入）")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

// MARK: - 通用 Tab（v15.18 · 默认合约 / 启动恢复 / 行情频率 / 反馈入口）

private struct GeneralSettingsTab: View {

    @AppStorage("settings.defaultInstrumentID") private var defaultInstrument: String = "RB0"
    @AppStorage("settings.restoreLastSession") private var restoreLastSession: Bool = true
    @AppStorage("settings.pollingIntervalSec") private var pollingIntervalSec: Double = 5.0
    /// v15.97 · 启动恢复上次工作区（active 模板 broadcast .workspaceTemplateActivated · M5+ 多窗口消费）
    @AppStorage(WorkspaceRestoreDefaults.restoreEnabledKey)
    private var restoreLastWorkspace: Bool = WorkspaceRestoreDefaults.restoreEnabledDefault

    private static let availableInstruments = [
        "RB0", "IF0", "AU0", "CU0", "AG0", "I0", "TA0", "MA0"
    ]

    var body: some View {
        Form {
            Section {
                Picker("默认合约", selection: $defaultInstrument) {
                    ForEach(Self.availableInstruments, id: \.self) { id in
                        Text(id).tag(id)
                    }
                }
                Toggle("启动时恢复上次合约 / 周期", isOn: $restoreLastSession)
                Toggle("启动时恢复上次工作区（v15.97）", isOn: $restoreLastWorkspace)
            } header: {
                Text("启动行为").font(.headline)
            } footer: {
                Text("修改后下次启动生效 · 工作区恢复触发 .workspaceTemplateActivated · M5+ 多窗口消费时自动应用模板布局")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Section {
                HStack {
                    Text("行情轮询间隔")
                    Spacer()
                    Text("\(Int(pollingIntervalSec)) 秒")
                        .font(.system(size: 12, design: .monospaced))
                }
                Slider(value: $pollingIntervalSec, in: 1...30, step: 1)
            } header: {
                Text("行情").font(.headline)
            } footer: {
                Text("Sina 免费源 · 默认 5 秒（建议 3-5 秒 · 太短易被限流 · 太长延时大）· 修改后重启生效")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Section {
                HStack(spacing: 12) {
                    Button("导出偏好…") { exportPreferences() }
                    Button("导入偏好…") { importPreferences() }
                }
            } header: {
                Text("备份 / 恢复").font(.headline)
            } footer: {
                Text("将当前偏好导出 JSON · 拷到新设备 / 重装时导入恢复（不含订单 / 资金等运行时数据）")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Section {
                Text("反馈渠道见项目 README · 内测期欢迎在内测群直接反馈")
                    .font(.system(size: 12))
                Text("版本：v15.18 · Stage A · 距 Legacy ~99.95%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            } header: {
                Text("帮助").font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    private func exportPreferences() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.title = L("导出偏好为 JSON")
        let dateStr = ISO8601DateFormatter().string(from: Date()).prefix(10)
        panel.nameFieldStringValue = "futures-terminal-prefs-\(dateStr).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = PreferenceExporter.export()
        try? data.write(to: url)
    }

    private func importPreferences() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = L("选择偏好 JSON")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let written = try PreferenceExporter.import(from: data)
            let alert = NSAlert()
            alert.messageText = L("导入完成")
            alert.informativeText = "已写入 \(written) 项偏好 · 重启 App 后生效"
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = L("导入失败")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.runModal()
        }
    }
}

// MARK: - 隐私 Tab（v15.18 · StageA-补遗 G2 §隐私"用户可在设置一键关闭埋点"）

private struct PrivacySettingsTab: View {

    @AppStorage("featureFlag.analytics.enabled") private var analyticsOn: Bool = FeatureFlag.analyticsEnabled.defaultValue
    @Environment(\.analytics) private var analytics
    @State private var totalEvents: Int = 0
    @State private var pendingEvents: Int = 0

    var body: some View {
        Form {
            Section {
                Toggle("启用匿名使用埋点（帮助产品改进）", isOn: $analyticsOn)
            } header: {
                Text("数据采集").font(.headline)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("我们采集匿名事件（启动 / 图表打开 / 指标添加 / 画线 / 预警触发等）用于改进体验。")
                    Text("**绝不采集**：交易订单 / 资金金额 / 持仓明细 / 个人身份信息。")
                    Text("修改后需重启生效。")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }

            // v15.18 · 透明度：让用户看到已记录 / 待上报事件数（增强信任 · D1 §4 隐私体验）
            Section {
                LabeledContent("本地已记录") {
                    Text("\(totalEvents) 条")
                        .font(.system(size: 12, design: .monospaced))
                }
                LabeledContent("待上报") {
                    Text("\(pendingEvents) 条")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(pendingEvents > 0 ? .orange : .secondary)
                }
            } header: {
                Text("数据透明度").font(.headline)
            } footer: {
                Text("后端 WP-80 就绪后 · driver 每 5min 自动批量上报 · 失败重试")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .task {
            await refreshStats()
        }
    }

    private func refreshStats() async {
        guard let svc = analytics else { return }
        let total = (try? await svc.storeCount()) ?? 0
        let pending = (try? await svc.queryPending(limit: 0).count) ?? 0
        await MainActor.run {
            totalEvents = total
            pendingEvents = pending
        }
    }
}

// MARK: - 图表 Tab（v17.92 · 指标默认参数 + K 线配色 + 价格精度）

private struct ChartSettingsTab: View {

    @State private var book: IndicatorParamsBook = IndicatorParamsStore.load() ?? .default
    @State private var candleMode: CandleColorMode = ChartSettingsStore.loadCandleColorMode()
    @State private var pricePrecision: PricePrecisionMode = ChartSettingsStore.loadPricePrecision()

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("MA 周期").font(.callout)
                    Spacer()
                    intStepper($book.mainMAPeriods, idx: 0, range: 2...250, width: 70)
                    Text("/").foregroundColor(.secondary)
                    intStepper($book.mainMAPeriods, idx: 1, range: 2...250, width: 70)
                    Text("/").foregroundColor(.secondary)
                    intStepper($book.mainMAPeriods, idx: 2, range: 2...250, width: 70)
                }
                HStack {
                    Text("BOLL 参数").font(.callout)
                    Spacer()
                    intStepper($book.mainBOLLParams, idx: 0, range: 5...100, width: 70)
                    Text("× σ").foregroundColor(.secondary)
                    intStepper($book.mainBOLLParams, idx: 1, range: 1...4, width: 70)
                }
            } header: {
                Text("主图指标默认").font(.headline)
            } footer: {
                Text("新建图表时默认参数 · 已打开的图表不影响（指标右键 → 参数 仍可单独覆盖）")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }

            Section {
                HStack {
                    Text("MACD").font(.callout)
                    Spacer()
                    intStepper($book.macdParams, idx: 0, range: 2...50, width: 55)
                    Text("/").foregroundColor(.secondary)
                    intStepper($book.macdParams, idx: 1, range: 2...100, width: 55)
                    Text("/").foregroundColor(.secondary)
                    intStepper($book.macdParams, idx: 2, range: 2...50, width: 55)
                }
                HStack {
                    Text("KDJ").font(.callout)
                    Spacer()
                    intStepper($book.kdjParams, idx: 0, range: 2...50, width: 55)
                    Text("/").foregroundColor(.secondary)
                    intStepper($book.kdjParams, idx: 1, range: 1...10, width: 55)
                    Text("/").foregroundColor(.secondary)
                    intStepper($book.kdjParams, idx: 2, range: 1...10, width: 55)
                }
                HStack {
                    Text("RSI 周期").font(.callout)
                    Spacer()
                    Stepper(value: $book.rsiPeriod, in: 2...50) {
                        Text("\(book.rsiPeriod)")
                            .font(.callout.monospaced())
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                Text("副图指标默认").font(.headline)
            }

            Section {
                Picker("涨跌配色", selection: $candleMode) {
                    ForEach(CandleColorMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("K 线配色").font(.headline)
            } footer: {
                Text("默认涨红跌绿（中国习惯）· 切换后下次 K 线图渲染生效")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }

            Section {
                Picker("价格精度", selection: $pricePrecision) {
                    ForEach(PricePrecisionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("价格显示").font(.headline)
            } footer: {
                Text("自动模式按合约规则推算（如螺纹 1 位、白银 0 位）· 固定模式强制覆盖")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }

            Section {
                Button("恢复全部默认") { resetAll() }
                    .foregroundColor(.red)
            } footer: {
                Text("仅重置图表偏好（指标 / 配色 / 精度）· 不影响通用 / 通知 / 隐私 tab")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onChange(of: book) { newValue in
            IndicatorParamsStore.save(newValue)
        }
        .onChange(of: candleMode) { newValue in
            ChartSettingsStore.saveCandleColorMode(newValue)
        }
        .onChange(of: pricePrecision) { newValue in
            ChartSettingsStore.savePricePrecision(newValue)
        }
    }

    private func intStepper(_ binding: Binding<[Int]>, idx: Int, range: ClosedRange<Int>, width: CGFloat) -> some View {
        Stepper(value: Binding(
            get: { binding.wrappedValue[idx] },
            set: { newValue in
                guard binding.wrappedValue.indices.contains(idx) else { return }
                var arr = binding.wrappedValue
                arr[idx] = newValue
                binding.wrappedValue = arr
            }
        ), in: range) {
            Text("\(binding.wrappedValue[idx])")
                .font(.callout.monospaced())
                .frame(width: width - 30, alignment: .trailing)
        }
        .frame(width: width)
    }

    private func resetAll() {
        let alert = NSAlert()
        alert.messageText = L("恢复图表偏好默认")
        alert.informativeText = "将重置指标参数 + K 线配色 + 价格精度 · 不可撤销"
        alert.addButton(withTitle: L("确认重置"))
        alert.addButton(withTitle: L("取消"))
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        book = .default
        candleMode = .redUpGreenDown
        pricePrecision = .auto
        IndicatorParamsStore.save(.default)
        ChartSettingsStore.resetAll()
    }
}

// MARK: - 通知 Tab（v15.18 · WP-23 FeatureFlag wire · alertSystemNotification + alertSound）

private struct NotificationSettingsTab: View {

    @AppStorage("featureFlag.alert.systemNotification") private var systemNotificationOn: Bool = FeatureFlag.alertSystemNotification.defaultValue
    @AppStorage("featureFlag.alert.sound") private var soundOn: Bool = FeatureFlag.alertSound.defaultValue
    @AppStorage("featureFlag.alert.center") private var centerOn: Bool = FeatureFlag.alertCenter.defaultValue

    var body: some View {
        Form {
            Section {
                Toggle("启用预警中心（条件触发评估）", isOn: $centerOn)
                Toggle("系统通知（macOS 通知中心横幅）", isOn: $systemNotificationOn)
                Toggle("声音提醒（NSSound Glass）", isOn: $soundOn)
            } header: {
                Text("预警通知").font(.headline)
            } footer: {
                Text("修改后需重启应用生效（dispatcher 在启动时按当前偏好装配 channels · v15.18 简化策略）")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

#endif
