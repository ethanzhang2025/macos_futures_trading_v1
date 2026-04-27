// MainApp · 自选 / 偏好设置占位 Scene
//
// spike 阶段只验证多窗口路径是否打通；真实 UI 留给后续 WP：
// - WatchlistContentView → WP-43 自选管理 UI 层
// - SettingsContentView  → WP-90 上线决策（订阅 / 账号 / 偏好）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI

// MARK: - 自选合约（stub · 待 WP-43 UI 层）

struct WatchlistContentView: View {

    var body: some View {
        VStack(spacing: 16) {
            Text("📋 自选合约")
                .font(.title)
            Text("（待 WP-43 自选管理 UI 接入）")
                .foregroundColor(.secondary)
            Text("数据模型层已就绪：WatchlistBook / 3 组 9 合约 / SQLite 持久化 ✅")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 480, idealWidth: 600, minHeight: 360, idealHeight: 480)
        .padding()
    }
}

// MARK: - 偏好设置（stub · 待 WP-90 / Settings Scene 真内容）

struct SettingsContentView: View {

    var body: some View {
        TabView {
            placeholder(title: "通用", note: "外观 / 启动行为 / 默认合约")
                .tabItem { Label("通用", systemImage: "gearshape") }
            placeholder(title: "图表", note: "颜色主题 / 默认指标 / 刻度精度")
                .tabItem { Label("图表", systemImage: "chart.line.uptrend.xyaxis") }
            placeholder(title: "数据", note: "行情源 / 缓存路径 / 加密 passphrase")
                .tabItem { Label("数据", systemImage: "externaldrive") }
            placeholder(title: "订阅", note: "Pro / Pro 500 / 设备绑定（待 WP-91）")
                .tabItem { Label("订阅", systemImage: "person.badge.key") }
        }
        .frame(width: 520, height: 360)
    }

    private func placeholder(title: String, note: String) -> some View {
        VStack(spacing: 12) {
            Text(title).font(.title2)
            Text(note).foregroundColor(.secondary)
            Text("（待后续 WP 接入）")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#endif
