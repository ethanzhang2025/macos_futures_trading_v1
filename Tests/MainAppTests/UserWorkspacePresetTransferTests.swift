// v17.137 · UserWorkspacePresetTransfer + ShellViewModel export/import 单测
//
// trader 场景：
// - 备份精心调好的预设（防误删 / 跨机器迁移）
// - 分享给同事或社区
//
// Linux 端 Shell 类全靠 MainApp 编译 · 走 macOS 守卫（Shell PoC 含 SwiftUI）
// macOS 实跑 · Linux 0 tests

#if canImport(SwiftUI) && os(macOS)

import Testing
import Foundation
@testable import MainApp

@Suite("UserWorkspacePresetTransfer · v17.137 导入导出")
struct UserWorkspacePresetTransferTests {

    private func makePreset(name: String = "盯盘") -> UserWorkspacePreset {
        UserWorkspacePreset(
            name: name,
            emoji: "🎯",
            primaryTab: .watching,
            paneLayout: .single,
            panes: [PaneConfig(kind: .chart, symbol: "RB0", periodRaw: "5m")]
        )
    }

    @Test("Transfer 容器 round-trip · 保留所有字段")
    func transferRoundTrip() throws {
        let presets = [makePreset(name: "早盘"), makePreset(name: "夜盘")]
        let transfer = UserWorkspacePresetTransfer(presets: presets)
        let data = try JSONEncoder().encode(transfer)
        let decoded = try JSONDecoder().decode(UserWorkspacePresetTransfer.self, from: data)
        #expect(decoded.schemaVersion == UserWorkspacePresetTransfer.currentSchemaVersion)
        #expect(decoded.presets.count == 2)
        #expect(decoded.presets[0].name == "早盘")
        #expect(decoded.presets[1].name == "夜盘")
    }

    @Test("旧 JSON（缺 schemaVersion / exportedAt）容错 decode")
    func legacyJSONFallback() throws {
        // 模拟极简旧文件 · 只有 presets 数组的 JSON
        let oldJSON = """
        {
          "presets": []
        }
        """
        let data = oldJSON.data(using: .utf8)!
        let transfer = try JSONDecoder().decode(UserWorkspacePresetTransfer.self, from: data)
        #expect(transfer.schemaVersion == 1)   // fallback 默认
        #expect(transfer.presets.isEmpty)
    }
}

@Suite("ShellViewModel · v17.137 export/import 用户预设")
@MainActor
struct ShellViewModelExportImportTests {

    private func makeVM() -> ShellViewModel {
        let vm = ShellViewModel()
        // 清空启动后默认载入的预设（确保起点干净）
        for p in vm.userPresets { vm.deleteUserPreset(p.id) }
        return vm
    }

    private func makePreset(name: String) -> UserWorkspacePreset {
        UserWorkspacePreset(
            name: name,
            emoji: "📊",
            primaryTab: .watching,
            paneLayout: .single,
            panes: [PaneConfig(kind: .chart, symbol: "RB0", periodRaw: "5m")]
        )
    }

    @Test("exportUserPresets · 空数组也能导出")
    func exportEmpty() {
        let vm = makeVM()
        let data = vm.exportUserPresets()
        #expect(data != nil)
        let decoded = try? JSONDecoder().decode(UserWorkspacePresetTransfer.self, from: data!)
        #expect(decoded?.presets.isEmpty == true)
    }

    @Test("export/import 往返 · append 模式追加")
    func roundTripAppend() throws {
        let vm = makeVM()
        vm.userPresets.append(makePreset(name: "早盘"))
        vm.userPresets.append(makePreset(name: "夜盘"))
        let exportedData = vm.exportUserPresets()!

        // 导入到全新 vm · append 模式
        let vm2 = makeVM()
        let result = try vm2.importUserPresets(data: exportedData, mode: .append)
        #expect(result.importedCount == 2)
        #expect(result.totalAfterImport == 2)
        #expect(vm2.userPresets.map(\.name).sorted() == ["夜盘", "早盘"])
    }

    @Test("import append · 不覆盖现有 · 不去重")
    func importAppendKeepsExisting() throws {
        let vm = makeVM()
        vm.userPresets.append(makePreset(name: "本机预设"))
        // 模拟一个外部导入的同名预设
        let external = makePreset(name: "本机预设")
        let externalData = try JSONEncoder().encode(UserWorkspacePresetTransfer(presets: [external]))
        _ = try vm.importUserPresets(data: externalData, mode: .append)
        #expect(vm.userPresets.count == 2)   // 同名也追加（不去重 · UUID 不同）
    }

    @Test("import replaceAll · 清空现有")
    func importReplaceAll() throws {
        let vm = makeVM()
        vm.userPresets.append(makePreset(name: "旧 1"))
        vm.userPresets.append(makePreset(name: "旧 2"))
        let newData = try JSONEncoder().encode(UserWorkspacePresetTransfer(presets: [
            makePreset(name: "新 A"),
            makePreset(name: "新 B"),
            makePreset(name: "新 C")
        ]))
        let result = try vm.importUserPresets(data: newData, mode: .replaceAll)
        #expect(result.importedCount == 3)
        #expect(result.totalAfterImport == 3)
        #expect(vm.userPresets.map(\.name) == ["新 A", "新 B", "新 C"])
    }

    @Test("import · 全部生成新 UUID 防与现有 / 文件内重复")
    func importRegeneratesUUIDs() throws {
        let vm = makeVM()
        let originalID = UUID()
        let preset = UserWorkspacePreset(
            id: originalID,
            name: "test",
            emoji: "🎯",
            primaryTab: .watching,
            paneLayout: .single,
            panes: []
        )
        let data = try JSONEncoder().encode(UserWorkspacePresetTransfer(presets: [preset]))
        _ = try vm.importUserPresets(data: data, mode: .append)
        #expect(vm.userPresets.first?.id != originalID)   // UUID 被重新生成
    }

    @Test("import · 空 data → throws fileEmpty")
    func importEmptyDataThrows() {
        let vm = makeVM()
        do {
            _ = try vm.importUserPresets(data: Data(), mode: .append)
            Issue.record("应该抛 fileEmpty")
        } catch WorkspacePresetImportError.fileEmpty {
            // 期望
        } catch {
            Issue.record("应该抛 fileEmpty · 实际抛: \(error)")
        }
    }

    @Test("import · 非 JSON → throws invalidJSON")
    func importInvalidJSONThrows() {
        let vm = makeVM()
        let badData = "this is not json".data(using: .utf8)!
        do {
            _ = try vm.importUserPresets(data: badData, mode: .append)
            Issue.record("应该抛 invalidJSON")
        } catch WorkspacePresetImportError.invalidJSON {
            // 期望
        } catch {
            Issue.record("应该抛 invalidJSON · 实际抛: \(error)")
        }
    }

    @Test("import · 未来 schema 版本 → throws unsupportedSchemaVersion")
    func importFutureSchemaThrows() throws {
        let vm = makeVM()
        // 手构 JSON · schemaVersion 设为未来版本
        let json = """
        {
          "schemaVersion": 999,
          "exportedAt": 0,
          "presets": []
        }
        """
        do {
            _ = try vm.importUserPresets(data: json.data(using: .utf8)!, mode: .append)
            Issue.record("应该抛 unsupportedSchemaVersion")
        } catch WorkspacePresetImportError.unsupportedSchemaVersion(let v) {
            #expect(v == 999)
        } catch {
            Issue.record("应该抛 unsupportedSchemaVersion · 实际抛: \(error)")
        }
    }
}

#endif
