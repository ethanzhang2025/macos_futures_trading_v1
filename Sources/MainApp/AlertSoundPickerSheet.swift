// MainApp · v17.86 · 预警声音选择器 sheet（AlertWindow 🔈 入口）
//
// trader 在 AlertCore SoundChannel 全局默认音之外手动切 · 试听 + 保存 UserDefaults
// 切换后下次 AlertWindow 启动 registerChannels 会读 UserDefaults 应用新音

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import AlertCore

struct AlertSoundPickerSheet: View {

    @Binding var isPresented: Bool

    @AppStorage(SoundChannelConstants.userDefaultsKey) private var soundName: String = "Funk"
    @State private var pendingName: String = "Funk"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            soundList
            Divider()
            footer
        }
        .frame(width: 440, height: 520)
        .onAppear { pendingName = soundName }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("🔈 预警声音").font(.title3.bold())
            Text("点击试听 · 选中后「保存」生效（下次预警触发时使用）")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var soundList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(SoundChannelConstants.availableSounds, id: \.self) { name in
                    soundRow(name)
                    Divider().opacity(0.3)
                }
            }
        }
    }

    private func soundRow(_ name: String) -> some View {
        Button {
            pendingName = name
            NSSound(named: name)?.play()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: pendingName == name ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(pendingName == name ? .accentColor : .secondary.opacity(0.5))
                Text(name)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
                Text("试听")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Text("当前：\(soundName)")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
            Spacer()
            Button("取消") { isPresented = false }
                .keyboardShortcut(.cancelAction)
            Button("保存") {
                soundName = pendingName
                isPresented = false
            }
            .keyboardShortcut(.defaultAction)
            .disabled(pendingName == soundName)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#endif
