import SwiftUI
import AppKit

/// K线图上的内联文字编辑器
struct InlineTextEditor: View {
    @Binding var text: String
    @Binding var editorWidth: CGFloat
    @Binding var editorHeight: CGFloat
    let position: CGPoint
    let onCommit: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            TextEditor(text: $text)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .background(Theme.panelBackground)
                .focused($isFocused)
                .frame(width: editorWidth, height: editorHeight)

            HStack(spacing: 6) {
                Spacer()
                Button("取消") { onCancel() }
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
                    .buttonStyle(.plain)
                Button("确定") { onCommit() }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.ma5)
                    .buttonStyle(.plain)
                // 拖拽调整大小
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 20, height: 16)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                editorWidth = max(100, editorWidth + value.translation.width / 8)
                                editorHeight = max(30, editorHeight + value.translation.height / 8)
                            }
                    )
                    .onHover { inside in
                        if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
                    }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(width: editorWidth)
            .background(Theme.panelBackground.opacity(0.95))
        }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.ma5, lineWidth: 1.5))
        .cornerRadius(4)
        .shadow(color: .black.opacity(0.5), radius: 8)
        .position(x: max(editorWidth / 2 + 60, position.x),
                  y: max(editorHeight / 2 + 20, position.y))
        .onAppear { isFocused = true }
    }
}
