// 添加自定义价差对 sheet（v15.75 · ⌘⌥W "+ 自定义对" 入口）
//
// trader 用法：选两条腿合约 + 比率 + 名称 → 保存 → 加入 ⌘⌥W 26 对扫描列表
//
// 设计要点：
// - leg1 / leg2 instrumentID 来自 SectorPresets.all（与异常监控同口径 60+ 主流合约）
// - leg1 ratio 默认 1（多腿）· leg2 ratio 默认 -1（空腿）· Stepper 范围 1-100 / -100--1
// - id 自动生成：custom-{leg1}-{leg2}-{ratio2 abs} · 保证可读 + 防撞
// - 保存前校验：leg1 ≠ leg2 / 名称非空

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import Shared
import DataCore

struct AddCustomSpreadPairSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var leg1ID: String = "RB0"
    @State private var leg2ID: String = "HC0"
    @State private var leg1Ratio: Int = 1
    @State private var leg2Ratio: Int = -1
    @State private var unitLabel: String = "元/吨"
    @State private var category: SpreadPair.Category = .跨品种

    let onSave: (SpreadPair) -> Void

    private var allInstruments: [SectorInstrument] { SectorPresets.all }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && leg1ID != leg2ID
            && leg1Ratio != 0
            && leg2Ratio != 0
    }

    private var generatedID: String {
        let leg1Prefix = leg1ID.lowercased().replacingOccurrences(of: "0", with: "")
        let leg2Prefix = leg2ID.lowercased().replacingOccurrences(of: "0", with: "")
        let ratioSuffix = abs(leg2Ratio) > 1 ? "-\(abs(leg2Ratio))" : ""
        return "custom-\(leg1Prefix)-\(leg2Prefix)\(ratioSuffix)"
    }

    private var spreadPreview: String {
        let r1 = leg1Ratio == 1 ? "" : "\(leg1Ratio) × "
        let r2sign = leg2Ratio < 0 ? "-" : "+"
        let r2abs = abs(leg2Ratio) == 1 ? "" : "\(abs(leg2Ratio)) × "
        return "\(r1)\(leg1ID) \(r2sign) \(r2abs)\(leg2ID)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("添加自定义价差对")
                .font(.title3.bold())

            Form {
                Section("基本信息") {
                    HStack {
                        Text("名称").frame(width: 60, alignment: .leading)
                        TextField("如：螺纹铜对", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Text("分类").frame(width: 60, alignment: .leading)
                        Picker("", selection: $category) {
                            ForEach(SpreadPair.Category.allCases, id: \.self) { c in
                                Text(c.rawValue).tag(c)
                            }
                        }
                        .labelsHidden()
                    }
                    HStack {
                        Text("单位").frame(width: 60, alignment: .leading)
                        TextField("元/吨 / 点 / 元", text: $unitLabel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        Spacer()
                    }
                }

                Section("第 1 腿（多腿）") {
                    HStack {
                        Text("合约").frame(width: 60, alignment: .leading)
                        instrumentPicker(selection: $leg1ID)
                    }
                    HStack {
                        Text("比率").frame(width: 60, alignment: .leading)
                        Stepper(value: $leg1Ratio, in: 1...100, step: 1) {
                            Text("\(leg1Ratio)")
                                .font(.callout.monospaced())
                                .frame(width: 40, alignment: .leading)
                        }
                        .frame(width: 130)
                        Spacer()
                    }
                }

                Section("第 2 腿（空腿）") {
                    HStack {
                        Text("合约").frame(width: 60, alignment: .leading)
                        instrumentPicker(selection: $leg2ID)
                    }
                    HStack {
                        Text("比率").frame(width: 60, alignment: .leading)
                        Stepper(value: $leg2Ratio, in: -100...(-1), step: 1) {
                            Text("\(leg2Ratio)")
                                .font(.callout.monospaced())
                                .frame(width: 40, alignment: .leading)
                        }
                        .frame(width: 130)
                        Spacer()
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("公式预览").font(.caption).foregroundColor(.secondary)
                    Text(spreadPreview).font(.callout.monospaced())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ID 预览").font(.caption).foregroundColor(.secondary)
                    Text(generatedID).font(.caption.monospaced()).foregroundColor(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    let pair = SpreadPair(
                        id: generatedID,
                        name: name.trimmingCharacters(in: .whitespaces),
                        category: category,
                        leg1: SpreadLeg(instrumentID: leg1ID, ratio: leg1Ratio),
                        leg2: SpreadLeg(instrumentID: leg2ID, ratio: leg2Ratio),
                        unitLabel: unitLabel.trimmingCharacters(in: .whitespaces),
                        description: "用户自建（\(spreadPreview)）"
                    )
                    onSave(pair)
                    dismiss()
                } label: {
                    Text("保存").bold()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 540, height: 540)
    }

    private func instrumentPicker(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            ForEach(allInstruments) { inst in
                Text("\(inst.id) · \(inst.name)（\(inst.sector.displayName)）")
                    .tag(inst.id)
            }
        }
        .labelsHidden()
        .frame(width: 320)
    }
}

#endif
