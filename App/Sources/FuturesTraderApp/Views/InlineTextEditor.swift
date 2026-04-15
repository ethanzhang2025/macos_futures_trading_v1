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
        VStack(alignment: .trailing, spacing: 0) {
            // 编辑区域
            TextEditor(text: $text)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .background(Theme.panelBackground)
                .focused($isFocused)
                .frame(width: editorWidth, height: editorHeight)

            // 底部操作栏
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

                // 拖拽调整大小手柄
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 20, height: 16)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                editorWidth = max(120, editorWidth + value.translation.width / 10)
                                editorHeight = max(30, editorHeight + value.translation.height / 10)
                            }
                    )
                    .onHover { inside in
                        if inside { NSCursor.resizeUpDown.push() }
                        else { NSCursor.pop() }
                    }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(width: editorWidth)
            .background(Theme.panelBackground.opacity(0.95))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Theme.ma5, lineWidth: 1.5)
        )
        .cornerRadius(4)
        .shadow(color: .black.opacity(0.5), radius: 8)
        .position(x: max(editorWidth / 2 + 60, position.x),
                  y: max(editorHeight / 2 + 20, position.y))
        .onAppear {
            isFocused = true
        }
    }
}
