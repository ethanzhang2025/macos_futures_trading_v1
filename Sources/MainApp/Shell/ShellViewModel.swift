// MainApp · Shell · v17.0 PoC Step 1
// Shell 主 ViewModel · @MainActor ObservableObject
// 持有所有 Shell 级状态（primaryTab / workspaces / layout / groupBindings）
// 持久化到 @AppStorage JSON

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import Foundation

@MainActor
public final class ShellViewModel: ObservableObject {

    // MARK: - 一级模块

    @Published public var primaryTab: PrimaryTab = .watching {
        didSet { persistPrimaryTab() }
    }

    // MARK: - 二级 Tab（Workspace）

    @Published public var workspaces: [Workspace] = []
    @Published public var activeWorkspaceID: UUID? = nil {
        didSet { persistActiveWorkspaceID() }
    }

    public var activeWorkspace: Workspace? {
        guard let id = activeWorkspaceID else { return nil }
        return workspaces.first { $0.id == id }
    }

    // MARK: - 布局状态

    @Published public var layout: ShellLayout = ShellLayout() {
        didSet { persistLayout() }
    }

    // MARK: - 彩色 group 联动（v17.1 实装 · Step 1 占位）

    @Published public var groupBindings: [GroupColor: SymbolBinding] = [:]

    // MARK: - v17.2 · 全局命令面板

    @Published public var showCommandPalette: Bool = false

    /// v17.29 · ⌘K 最近用过的命令 title 列表（LRU · 最多 5 个 · UserDefaults 持久化）
    @Published public var recentPaletteCommands: [String] = []

    // MARK: - v17.5 · Pane 最大化（文华 Enter/Esc 二态切换 · 单 Pane 占满主区）

    @Published public var maximizedPaneID: UUID? = nil

    public func toggleMaximize(_ paneID: UUID) {
        if maximizedPaneID == paneID {
            maximizedPaneID = nil
        } else {
            maximizedPaneID = paneID
        }
    }

    public func exitMaximize() {
        maximizedPaneID = nil
    }

    // MARK: - v17.57 · F 键体系（文华 trader 兼容 · v17.0 P0.4）

    /// F 键触发的瞬态 toast（ShellWindow overlay 显示 ~1.5s 自动消失）
    @Published public var fKeyToast: String? = nil

    /// F6 / sidebar focus trigger（每按一次 += 1 · ShellSidebar 监听）
    @Published public var sidebarFocusTrigger: Int = 0

    /// F10 合约资料 sheet（v1 显示当前 active pane symbol · v2 接 InstrumentDashboardWindow 详情）
    @Published public var showInstrumentInfoSheet: Bool = false

    /// v17.67 · 预设选择 sheet（WorkspaceTabBar + Menu「从预设新建...」触发）
    @Published public var showPresetPickerSheet: Bool = false

    /// 空格快捷下单浮层（v1 占位 · Stage A 不接 CTP · v2 接 SimulatedTradingEngine 浮窗）
    @Published public var showQuickOrderSheet: Bool = false

    /// F6 · 聚焦左 sidebar 自选 section
    public func focusSidebar() {
        sidebarFocusTrigger &+= 1
        flashToast("F6 · 跳焦自选")
    }

    /// F8 · 当前 active workspace 第一 Pane（或 maximized）周期循环
    public func cyclePeriodOnActivePane() {
        guard let wsIdx = workspaces.firstIndex(where: { $0.id == activeWorkspaceID }) else { return }
        let paneIdx: Int
        if let mid = maximizedPaneID,
           let pi = workspaces[wsIdx].panes.firstIndex(where: { $0.id == mid }) {
            paneIdx = pi
        } else if let pi = workspaces[wsIdx].panes.indices.first {
            paneIdx = pi
        } else { return }
        let cycle = Self.fKeyPeriodCycle
        let cur = workspaces[wsIdx].panes[paneIdx].periodRaw ?? "1m"
        let next = cycle[((cycle.firstIndex(of: cur) ?? -1) + 1) % cycle.count]
        workspaces[wsIdx].panes[paneIdx].periodRaw = next
        // 广播到同组（彩色 group 联动 · 跨 workspace）
        if let color = workspaces[wsIdx].panes[paneIdx].groupColor {
            groupBindings[color]?.periodRaw = next
            for wIdx in workspaces.indices {
                for pIdx in workspaces[wIdx].panes.indices
                    where workspaces[wIdx].panes[pIdx].groupColor == color {
                    workspaces[wIdx].panes[pIdx].periodRaw = next
                }
            }
        }
        persistWorkspaces()
        flashToast("F8 · 周期 → \(Self.periodDisplayName(next))")
    }

    /// F10 · 显示当前 Pane 合约资料 sheet
    public func openInstrumentInfo() {
        showInstrumentInfoSheet = true
        flashToast("F10 · 合约资料")
    }

    /// F12 · 画线工具 hint（实际工具在 Chart 工具栏 / 右键菜单）
    public func hintDrawingTool() {
        flashToast("F12 · 画线工具在 Pane 顶部工具栏 / 右键菜单")
    }

    /// 空格 · 唤起下单浮层（Stage A 占位 · 后续接 SimulatedTradingEngine）
    public func openQuickOrder() {
        showQuickOrderSheet = true
        flashToast("空格 · 模拟下单浮层")
    }

    private static let fKeyPeriodCycle: [String] = [
        "1m", "5m", "15m", "30m", "1h", "4h", "D", "W", "M"
    ]

    private static func periodDisplayName(_ raw: String) -> String {
        switch raw {
        case "1m": return "1 分"
        case "3m": return "3 分"
        case "5m": return "5 分"
        case "15m": return "15 分"
        case "30m": return "30 分"
        case "1h": return "1 时"
        case "2h": return "2 时"
        case "4h": return "4 时"
        case "D":  return "日线"
        case "W":  return "周线"
        case "M":  return "月线"
        default:   return raw
        }
    }

    /// 瞬态 toast helper（1.5s 后自动清空 · 多次按只显示最新）
    private var toastClearTask: Task<Void, Never>?
    private func flashToast(_ s: String) {
        fKeyToast = s
        toastClearTask?.cancel()
        toastClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.fKeyToast = nil }
        }
    }

    // MARK: - v17.66 · Tab Detach 持久化（重启恢复 detached NSWindow）

    /// 已分离为独立 NSWindow 的 Pane ID 字符串列表（UserDefaults 持久化）
    /// onAppear 时由 ShellWindow restore · markPaneDetached / markPaneAttached 维护
    public var detachedPaneIDStrings: [String] = [] {
        didSet { persistDetachedPaneIDs() }
    }

    /// App 进程内是否已恢复过 detached 窗口（防多 ShellWindow 重复 openWindow）
    public var hasRestoredDetachedWindows: Bool = false

    /// App 是否正在退出（NSApplication.willTerminateNotification 触发）
    /// 退出时 detached window 全部 .onDisappear 会误清空 detachedPaneIDStrings · 此 flag 用于跳过
    public var isApplicationTerminating: Bool = false

    /// 标记 Pane 为已分离（PaneHeader 📤 按钮触发）
    public func markPaneDetached(paneID: UUID) {
        let s = paneID.uuidString
        guard !detachedPaneIDStrings.contains(s) else { return }
        detachedPaneIDStrings.append(s)
    }

    /// 标记 Pane 为已合并回 Shell（DetachedPaneWindow .onDisappear 触发 · 覆盖 ⌘W / X / 合并按钮 各种关窗路径）
    /// App 退出时跳过（detached window 集体 .onDisappear 会误清空 · 下次启动需要保留 list 恢复）
    public func markPaneAttached(paneID: UUID) {
        guard !isApplicationTerminating else { return }
        let s = paneID.uuidString
        detachedPaneIDStrings.removeAll { $0 == s }
    }

    /// restore 时筛除已不存在的 paneID（用户可能在重启前删除 pane）· 返回有效 paneID 列表
    public func validDetachedPaneIDsForRestore() -> [UUID] {
        let allPaneIDs = Set(workspaces.flatMap { $0.panes.map(\.id) })
        let valid = detachedPaneIDStrings.compactMap { UUID(uuidString: $0) }.filter { allPaneIDs.contains($0) }
        let validStrings = Set(valid.map(\.uuidString))
        if validStrings.count != detachedPaneIDStrings.count {
            detachedPaneIDStrings = detachedPaneIDStrings.filter { validStrings.contains($0) }
        }
        return valid
    }

    // MARK: - 初始化

    public init() {
        loadFromStorage()
    }

    // MARK: - Workspace 操作

    public func newWorkspace(name: String? = nil) {
        let count = workspaces.filter { $0.primaryTab == primaryTab }.count
        let defaultName = name ?? "\(primaryTab.displayName) \(count + 1)"
        let ws = Workspace(
            name: defaultName,
            primaryTab: primaryTab,
            paneLayout: .single,
            panes: [PaneConfig(kind: primaryTab.defaultPaneKind)]
        )
        workspaces.append(ws)
        activeWorkspaceID = ws.id
        persistWorkspaces()
    }

    /// v17.67 · 从内置预设新建 Workspace（一键应用完整 panes + layout + recommendedPrimaryTab）
    public func newWorkspace(from preset: WorkspacePreset) {
        let ws = preset.toWorkspace()
        workspaces.append(ws)
        primaryTab = ws.primaryTab
        activeWorkspaceID = ws.id
        persistWorkspaces()
    }

    public func closeWorkspace(_ id: UUID) {
        guard workspaces.count > 1 else { return }  // 至少保留 1 个
        workspaces.removeAll { $0.id == id }
        if activeWorkspaceID == id {
            activeWorkspaceID = workspaces.first?.id
        }
        persistWorkspaces()
    }

    public func renameWorkspace(_ id: UUID, to newName: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[idx].name = newName
        persistWorkspaces()
    }

    /// 切到指定 workspace（更新 lastUsedAt）
    public func activate(_ id: UUID) {
        guard let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[idx].lastUsedAt = Date()
        activeWorkspaceID = id
        primaryTab = workspaces[idx].primaryTab
        persistWorkspaces()
    }

    /// 修改当前 active workspace 的 PaneLayout · 自动调整 panes 数组
    public func setPaneLayout(_ layout: PaneLayout) {
        guard let id = activeWorkspaceID,
              let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[idx].paneLayout = layout
        let target = layout.paneCount
        if target > 0 {
            let current = workspaces[idx].panes.count
            if target > current {
                // 补默认 Pane
                let defaultKind = workspaces[idx].primaryTab.defaultPaneKind
                for _ in 0..<(target - current) {
                    workspaces[idx].panes.append(PaneConfig(kind: defaultKind))
                }
            } else if target < current {
                workspaces[idx].panes = Array(workspaces[idx].panes.prefix(target))
            }
        }
        persistWorkspaces()
    }

    // MARK: - v17.1 · 彩色 group 联动

    /// 设定 Pane 的 group color · 若已有 binding 则同步 symbol 到该 Pane · 否则用 Pane symbol 初始化 binding
    public func setPaneGroupColor(paneID: UUID, color: GroupColor?) {
        guard let wsIdx = workspaceIndexContainingPane(paneID),
              let paneIdx = workspaces[wsIdx].panes.firstIndex(where: { $0.id == paneID }) else { return }
        workspaces[wsIdx].panes[paneIdx].groupColor = color
        if let c = color {
            if let existing = groupBindings[c] {
                // 已有 binding · Pane 跟随 group
                workspaces[wsIdx].panes[paneIdx].symbol = existing.symbol
                if let p = existing.periodRaw {
                    workspaces[wsIdx].panes[paneIdx].periodRaw = p
                }
            } else {
                // 首个加入该组 · Pane symbol 设入 binding
                let sym = workspaces[wsIdx].panes[paneIdx].symbol ?? "rb2510"
                groupBindings[c] = SymbolBinding(
                    symbol: sym,
                    periodRaw: workspaces[wsIdx].panes[paneIdx].periodRaw
                )
            }
        }
        persistWorkspaces()
    }

    /// Pane 改 symbol · 若有 group color 则广播到同组所有 Pane
    public func setPaneSymbol(paneID: UUID, symbol: String) {
        guard let wsIdx = workspaceIndexContainingPane(paneID),
              let paneIdx = workspaces[wsIdx].panes.firstIndex(where: { $0.id == paneID }) else { return }
        workspaces[wsIdx].panes[paneIdx].symbol = symbol
        if let color = workspaces[wsIdx].panes[paneIdx].groupColor {
            // 广播到同色所有 Pane（跨 workspace）
            groupBindings[color]?.symbol = symbol
            for wIdx in workspaces.indices {
                for pIdx in workspaces[wIdx].panes.indices {
                    if workspaces[wIdx].panes[pIdx].groupColor == color {
                        workspaces[wIdx].panes[pIdx].symbol = symbol
                    }
                }
            }
        }
        persistWorkspaces()
    }

    /// 获取 Pane 当前有效 symbol（若有 group 则取 group binding · 否则取 pane 自身）
    public func effectiveSymbol(for config: PaneConfig) -> String? {
        if let c = config.groupColor, let binding = groupBindings[c] {
            return binding.symbol
        }
        return config.symbol
    }

    // MARK: - v17.58 · 跨周期十字光标同步（v17.0 P1.2 · Alt+V 升级）
    //
    // ChartScene 嵌入 Shell · hover 时通过 Environment closure 上报 paneID + Date
    // → ShellVM 写入 groupBindings[color].crosshairUnixTime → 同 group 所有 Pane 收到广播
    // → 兄弟 Pane 在 PaneHeader 显示"🎯 联动光标 HH:MM:SS"badge
    // → ChartScene v18+ 接 effectiveCrosshair(for:) 直接画十字（深度集成）

    /// 设置某 Pane 的 crosshair（仅当 Pane 有 group color 时生效 · 广播到同组）
    /// v18 · 同时记录 source paneID · 用于 effectiveCrosshair 排除自身回流
    public func setPaneCrosshair(paneID: UUID, unixTime: Double?) {
        guard let wsIdx = workspaceIndexContainingPane(paneID),
              let pane = workspaces[wsIdx].panes.first(where: { $0.id == paneID }),
              let color = pane.groupColor else { return }
        if var binding = groupBindings[color] {
            binding.crosshairUnixTime = unixTime
            binding.crosshairSourcePaneIDString = unixTime == nil ? nil : paneID.uuidString
            groupBindings[color] = binding
        }
    }

    /// 清除某 Pane 的 crosshair（hover 离开 · 同上广播）
    public func clearPaneCrosshair(paneID: UUID) {
        setPaneCrosshair(paneID: paneID, unixTime: nil)
    }

    /// 获取 Pane 当前应显示的 crosshair（同 group 兄弟广播的时间）
    /// v18 · 排除自身回流（source == self 时返回 nil · 避免 ChartScene 重复画光标）
    public func effectiveCrosshair(for config: PaneConfig) -> Date? {
        guard let c = config.groupColor,
              let binding = groupBindings[c],
              let ts = binding.crosshairUnixTime else { return nil }
        if binding.crosshairSourcePaneIDString == config.id.uuidString { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    // MARK: - v17.20 Pane 右键 actions

    /// v17.29 · 记录 palette 命令使用（LRU · 最近 5 个 · 用于 ⌘K 默认 "最近" section）
    public func recordPaletteCommandUsage(_ title: String) {
        var list = recentPaletteCommands.filter { $0 != title }
        list.insert(title, at: 0)
        if list.count > 5 { list = Array(list.prefix(5)) }
        recentPaletteCommands = list
        UserDefaults.standard.set(list, forKey: "shell.v1.recentPaletteCommands")
    }

    // MARK: - v17.62 · Workspace 导入 / 导出 JSON（v17.0 设计 §13.2 v17.5）

    /// 导出指定 Workspace 为 JSON Data（不含 id · 导入端重生 UUID 防冲突）
    public func exportWorkspace(_ id: UUID) -> Data? {
        guard let ws = workspaces.first(where: { $0.id == id }) else { return nil }
        // 序列化时清掉 id 让导入端重生（防主键冲突 + panes 嵌套 id 同步重生）
        var copy = ws
        copy.id = UUID()  // 占位 · 导入端会再换
        copy.panes = copy.panes.map { p in
            var np = p
            np.id = UUID()
            return np
        }
        copy.createdAt = ws.createdAt  // 保留原创建时间作为 metadata
        copy.lastUsedAt = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(copy)
    }

    /// 从 JSON Data 导入 Workspace（新 UUID · 追加到末尾 · 自动激活）
    @discardableResult
    public func importWorkspace(from data: Data) -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var ws = try? decoder.decode(Workspace.self, from: data) else { return false }
        ws.id = UUID()
        ws.panes = ws.panes.map { p in
            var np = p
            np.id = UUID()
            // 清 group color 避免与现有 group 互相污染
            np.groupColor = nil
            return np
        }
        ws.lastUsedAt = Date()
        if !ws.name.contains("(导入)") {
            ws.name = "\(ws.name) (导入)"
        }
        workspaces.append(ws)
        activeWorkspaceID = ws.id
        primaryTab = ws.primaryTab
        persistWorkspaces()
        return true
    }

    /// 复制 Workspace（panes + layout 全复制 · name = "原名 副本"·新 UUID · 紧跟原 ws 之后插入并激活）
    public func duplicateWorkspace(_ id: UUID) {
        guard let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        var copy = workspaces[idx]
        copy.id = UUID()
        copy.name = "\(copy.name) 副本"
        copy.panes = copy.panes.map { p in
            var np = p
            np.id = UUID()
            return np
        }
        copy.lastUsedAt = Date()
        workspaces.insert(copy, at: idx + 1)
        activeWorkspaceID = copy.id
        persistWorkspaces()
    }

    /// 切换 Pane 类型（保留 symbol / period / group · 仅改 kind）
    public func changePaneKind(paneID: UUID, to kind: PaneKind) {
        guard let wsIdx = workspaceIndexContainingPane(paneID),
              let paneIdx = workspaces[wsIdx].panes.firstIndex(where: { $0.id == paneID }) else { return }
        workspaces[wsIdx].panes[paneIdx].kind = kind
        persistWorkspaces()
    }

    /// v17.68 · 添加 Pane 到当前 active Workspace（命令面板"新建 Pane"接通）
    /// 自动扩大 paneLayout 容纳新 Pane · paneCount 已满则 no-op（提示用户切大布局）
    public func addPaneToActiveWorkspace(kind: PaneKind) {
        guard let wsIdx = workspaces.firstIndex(where: { $0.id == activeWorkspaceID }) else { return }
        let target = workspaces[wsIdx].paneLayout.paneCount
        guard target > 0, workspaces[wsIdx].panes.count < target else { return }
        workspaces[wsIdx].panes.append(PaneConfig(kind: kind))
        persistWorkspaces()
    }

    /// v17.71 · 设定 Pane 周期（PaneHeader inline picker · 同 group 广播 · 与 cyclePeriodOnActivePane 共享广播逻辑）
    public func setPanePeriod(paneID: UUID, periodRaw: String) {
        guard let wsIdx = workspaces.firstIndex(where: { ws in ws.panes.contains { $0.id == paneID } }),
              let paneIdx = workspaces[wsIdx].panes.firstIndex(where: { $0.id == paneID }) else { return }
        workspaces[wsIdx].panes[paneIdx].periodRaw = periodRaw
        if let color = workspaces[wsIdx].panes[paneIdx].groupColor {
            groupBindings[color]?.periodRaw = periodRaw
            for wIdx in workspaces.indices {
                for pIdx in workspaces[wIdx].panes.indices
                    where workspaces[wIdx].panes[pIdx].groupColor == color {
                    workspaces[wIdx].panes[pIdx].periodRaw = periodRaw
                }
            }
        }
        persistWorkspaces()
    }

    /// v17.68 · 切换 Inspector 显隐（命令面板 + ⌘⌥I 快捷键 二入口）
    public func toggleInspector() {
        layout.inspectorVisible.toggle()
    }

    /// 重置 Pane 配置（清 symbol / period / group · 保留 kind）· 用于"恢复初始状态"
    public func resetPaneConfig(paneID: UUID) {
        guard let wsIdx = workspaceIndexContainingPane(paneID),
              let paneIdx = workspaces[wsIdx].panes.firstIndex(where: { $0.id == paneID }) else { return }
        workspaces[wsIdx].panes[paneIdx].symbol = nil
        workspaces[wsIdx].panes[paneIdx].periodRaw = nil
        workspaces[wsIdx].panes[paneIdx].groupColor = nil
        persistWorkspaces()
    }

    private func workspaceIndexContainingPane(_ paneID: UUID) -> Int? {
        workspaces.firstIndex { ws in ws.panes.contains { $0.id == paneID } }
    }

    // MARK: - 持久化

    private static let kWorkspaces = "shell.v1.workspaces"
    private static let kActiveID = "shell.v1.activeWorkspaceID"
    private static let kPrimaryTab = "shell.v1.primaryTab"
    private static let kLayout = "shell.v1.layout"
    private static let kDetachedPaneIDs = "shell.v1.detachedPaneIDs"

    private func loadFromStorage() {
        let ud = UserDefaults.standard
        // workspaces
        if let data = ud.data(forKey: Self.kWorkspaces),
           let arr = try? JSONDecoder().decode([Workspace].self, from: data),
           !arr.isEmpty {
            workspaces = arr
        } else {
            workspaces = Workspace.defaults()
        }
        // active workspace
        if let s = ud.string(forKey: Self.kActiveID),
           let id = UUID(uuidString: s),
           workspaces.contains(where: { $0.id == id }) {
            activeWorkspaceID = id
        } else {
            activeWorkspaceID = workspaces.first?.id
        }
        // primary tab
        if let raw = ud.string(forKey: Self.kPrimaryTab),
           let tab = PrimaryTab(rawValue: raw) {
            primaryTab = tab
        } else if let ws = activeWorkspace {
            primaryTab = ws.primaryTab
        }
        // layout
        if let data = ud.data(forKey: Self.kLayout),
           let l = try? JSONDecoder().decode(ShellLayout.self, from: data) {
            layout = l
        }
        // v17.29 · 最近用过的 ⌘K 命令（[String]）· 兼容 nil
        if let arr = ud.stringArray(forKey: "shell.v1.recentPaletteCommands") {
            recentPaletteCommands = arr
        }
        // v17.66 · detached paneID 列表（重启恢复 detached NSWindow）
        if let arr = ud.stringArray(forKey: Self.kDetachedPaneIDs) {
            detachedPaneIDStrings = arr
        }
    }

    private func persistWorkspaces() {
        if let data = try? JSONEncoder().encode(workspaces) {
            UserDefaults.standard.set(data, forKey: Self.kWorkspaces)
        }
    }

    private func persistActiveWorkspaceID() {
        UserDefaults.standard.set(activeWorkspaceID?.uuidString, forKey: Self.kActiveID)
    }

    private func persistPrimaryTab() {
        UserDefaults.standard.set(primaryTab.rawValue, forKey: Self.kPrimaryTab)
    }

    private func persistLayout() {
        if let data = try? JSONEncoder().encode(layout) {
            UserDefaults.standard.set(data, forKey: Self.kLayout)
        }
    }

    private func persistDetachedPaneIDs() {
        UserDefaults.standard.set(detachedPaneIDStrings, forKey: Self.kDetachedPaneIDs)
    }
}

#endif
