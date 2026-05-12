// MainApp · Shell · v17.59 · Tab Detach NSWindow 多屏支持
//
// v17.0 设计 §11 · P1.4 · 独立窗口仍受 group 联动控制（同 ShellViewModel）
//
// 设计要点：
//   - 通过 SwiftUI WindowGroup(for: String.self, id: "detachedPane") 注册
//   - openWindow(id: "detachedPane", value: paneID.uuidString) 触发
//   - 窗口内通过 paneID 反查 ShellViewModel.workspaces 找到对应 PaneConfig
//   - 复用 PaneBody · 共享 environment（含 shellHostedPaneID / shellCrosshairReporter / externalCrosshair）
//   - 头部含"合并回 Shell"按钮（关窗 = 合并）
//
// 持久化（v17.59 v1）：不持久化 detached state · 重启不恢复（M7+ 后接 NSWindow restorable）

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

struct DetachedPaneWindow: View {

    let paneIDString: String?
    @EnvironmentObject var shellVM: ShellViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let str = paneIDString, let id = UUID(uuidString: str),
           let config = lookupPaneConfig(id: id) {
            VStack(spacing: 0) {
                detachedHeader(config: config)
                Divider()
                PaneBody(config: config)
                    .environment(\.isHostedInShell, true)
                    .environment(\.shellHostedPaneID, config.id)
                    .environment(\.shellCrosshairReporter, { [weak shellVM] pid, date in
                        shellVM?.setPaneCrosshair(paneID: pid, unixTime: date?.timeIntervalSince1970)
                    })
                    .environment(\.shellExternalCrosshair, shellVM.effectiveCrosshair(for: config))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 800, minHeight: 500)
            .followingChartTheme()
            // v17.66 · 关窗即合并回 Shell · 覆盖 ⌘W / X / 合并按钮 各种路径 · 同步清 UserDefaults
            .onDisappear {
                shellVM.markPaneAttached(paneID: id)
            }
        } else {
            VStack(spacing: 8) {
                Text("📤 分离 Pane 已不存在")
                    .font(.title3)
                Text("原 Pane 可能已被删除或重建 · 关闭此窗口")
                    .font(.caption).foregroundColor(.secondary)
                Button("关闭") { dismiss() }
            }
            .padding(40)
            .frame(minWidth: 480, minHeight: 200)
            .onDisappear {
                if let str = paneIDString, let id = UUID(uuidString: str) {
                    shellVM.markPaneAttached(paneID: id)
                }
            }
        }
    }

    private func lookupPaneConfig(id: UUID) -> PaneConfig? {
        for ws in shellVM.workspaces {
            if let cfg = ws.panes.first(where: { $0.id == id }) {
                return cfg
            }
        }
        return nil
    }

    @ViewBuilder
    private func detachedHeader(config: PaneConfig) -> some View {
        HStack(spacing: 8) {
            Text(config.kind.emoji).font(.system(size: 13))
            Text(config.kind.displayName)
                .font(.system(size: 12, weight: .medium))
            if let sym = shellVM.effectiveSymbol(for: config) {
                Text("·").foregroundColor(.secondary)
                Text(sym)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.accentColor)
            }
            if let p = config.periodRaw {
                Text("·").foregroundColor(.secondary)
                Text(p)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            if let color = config.groupColor {
                Circle().fill(color.color).frame(width: 10, height: 10)
                Text(color.displayName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            // 跨周期同步 badge
            if let groupCrosshair = shellVM.effectiveCrosshair(for: config),
               config.groupColor != nil {
                Text("🎯 \(Self.timeFmt.string(from: groupCrosshair))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.7))
                    .cornerRadius(3)
            }
            Spacer()
            Text("📤 已分离")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Button {
                dismiss()
            } label: {
                Label("合并回 Shell", systemImage: "arrow.down.left.square")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("关窗 = 合并回 Shell（Pane 配置保留在 Shell workspace 内）")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: 32)
        .background(Color.accentColor.opacity(0.08))
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

#endif
