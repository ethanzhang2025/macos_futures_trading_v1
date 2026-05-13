// v17.169 · CSV 行情导入 sheet（trader 加自己历史数据入口）
//
// 流程：
// 1. NSOpenPanel 选 CSV
// 2. 读文件 · 调 KLineCSVImporter.parse
// 3. 显示结果（bar 数 / errors 数 / 检测格式 / 时间范围）
// 4. 接受 → 触发 onImport callback（caller 决定怎么用 · 入 SQLite / 临时回测等）
//
// 入口推荐：主菜单 "文件 → 导入 K 线 CSV..." · 或 ChartScene toolbar "···" submenu

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Shared
import UniformTypeIdentifiers

struct KLineCSVImportSheet: View {

    let onImport: (KLineCSVImportResult, _ instrumentID: String, _ period: KLinePeriod) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var instrumentID: String = "RB0"
    @State private var period: KLinePeriod = .minute1
    @State private var pickedURL: URL? = nil
    @State private var preview: KLineCSVImportResult? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CSV 行情导入")
                .font(.title2).bold()
            Text("trader 加自己 CSV 历史数据（券商 / Tushare / Wind / 通达信 / 文华 通吃）· 表头/无表头 + 5 种时间格式自动嗅探")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            Form {
                TextField("合约代码", text: $instrumentID)
                Picker("周期", selection: $period) {
                    ForEach(KLinePeriod.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
            }
            .frame(maxWidth: 320)

            HStack {
                Button("📂 选择 CSV 文件...") { pickFile() }
                if let url = pickedURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let preview = preview {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Label("解析成功 \(preview.bars.count) 根", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("检测时间格式：\(preview.detectedFormat)")
                        .font(.caption)
                    if let first = preview.bars.first, let last = preview.bars.last {
                        Text("时间范围：\(first.openTime.formatted(date: .abbreviated, time: .shortened)) → \(last.openTime.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                    }
                    if !preview.errors.isEmpty {
                        Label("解析错误 \(preview.errors.count) 行（已跳过）", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(preview.errors.prefix(20).enumerated()), id: \.offset) { _, msg in
                                    Text(msg).font(.system(size: 10, design: .monospaced))
                                }
                                if preview.errors.count > 20 {
                                    Text("...还有 \(preview.errors.count - 20) 条")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(maxHeight: 120)
                    }
                }
            }

            if let err = errorMessage {
                Label(err, systemImage: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Spacer()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("导入") {
                    if let preview {
                        onImport(preview, instrumentID, period)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(preview == nil || (preview?.bars.isEmpty ?? true))
            }
        }
        .padding(20)
        .frame(width: 540, height: 480)
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let csvUTI = UTType(filenameExtension: "csv") {
            panel.allowedContentTypes = [csvUTI]
        }
        if panel.runModal() == .OK, let url = panel.url {
            pickedURL = url
            errorMessage = nil
            preview = nil
            do {
                let csv = try String(contentsOf: url, encoding: .utf8)
                let result = try KLineCSVImporter.parse(csv: csv, instrumentID: instrumentID, period: period)
                preview = result
            } catch KLineCSVImporter.ImportError.emptyFile {
                errorMessage = "CSV 文件为空"
            } catch KLineCSVImporter.ImportError.noValidRows {
                errorMessage = "CSV 无有效数据行"
            } catch KLineCSVImporter.ImportError.timeFormatNotDetected {
                errorMessage = "无法识别时间格式 · 支持 yyyy-MM-dd / yyyy-MM-dd HH:mm:ss / yyyyMMdd / yyyyMMdd HHmmss / Unix"
            } catch {
                errorMessage = "读取失败：\(error)"
            }
        }
    }
}

#endif
