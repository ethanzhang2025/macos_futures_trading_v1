import SwiftUI
import AppKit

/// K线图上的内联文字编辑器
struct InlineTextEditor: View {
    @Binding var text: String
    let position: CGPoint
    let onCommit: () -> Void
    let onCancel: () -> Void

    @State private var editorWidth: CGFloat = 200
    @State private var editorHeight: CGFloat = 60
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 编辑区域
            TextEditor(text: $text)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .background(Theme.panelBackground)
                .focused($isFocused)
                .frame(width: editorWidth, height: editorHeight)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Theme.ma5, lineWidth: 1.5)
                )

            // 操作栏
            HStack(spacing: 8) {
                // 拖拽调整大小的提示
                Text("\(Int(editorWidth))×\(Int(editorHeight))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.textMuted)

                Spacer()

                Button("取消") { onCancel() }
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
                    .buttonStyle(.plain)

                Button("确定") { onCommit() }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.ma5)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .frame(width: editorWidth)
            .background(Theme.panelBackground.opacity(0.9))
            .cornerRadius(0)

            // 右下角拖拽调整大小的手柄
        }
        .position(x: max(editorWidth / 2 + 60, position.x), y: max(editorHeight / 2 + 20, position.y))
        .gesture(
            DragGesture()
                .onChanged { _ in } // 阻止拖拽穿透到K线图
        )
        .onAppear { isFocused = true }
        // 右下角拖拽调整大小
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            editorWidth = max(120, editorWidth + value.translation.width)
                            editorHeight = max(30, editorHeight + value.translation.height)
                        }
                )
                .position(x: max(editorWidth / 2 + 60, position.x) + editorWidth / 2 - 8,
                           y: max(editorHeight / 2 + 20, position.y) + editorHeight / 2 + 10)
                .cursor(.resizeUpDown)
        }
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
