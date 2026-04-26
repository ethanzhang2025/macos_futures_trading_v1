// Watchlist + Workspace SQLite 持久化端到端 demo（第 11 个真数据 demo）
//
// 用途：
// - 验证 WP-19a-5/6 在真实"持久化 → 进程退出 → 重启 → 恢复"链路下工作
// - 演示 UI 启动场景：用户重启 App 后自选 + 工作区完整恢复
// - 演示 corrupt-JSON 负向场景：脏 JSON 显式抛 decodeFailed（不静默吞数据）
//
// 拓扑（5 段）：
//   段 1 · 准备临时文件路径
//   段 2 · 写入 SQLite store（WatchlistBook 3 组 + WorkspaceBook 3 模板 · save + close）
//   段 3 · 模拟"进程重启" → 重新打开同 path → load 验证完整往返（==）
//   段 4 · 文件大小内省 + cleanup
//   段 5 · 负向场景：脏 JSON 触发 WatchlistBookStoreError.decodeFailed
//
// 运行：swift run WatchlistWorkspacePersistDemo
// 注意：纯本地 SQLite，不依赖 Sina 网络

import Foundation
import Shared

@main
struct WatchlistWorkspacePersistDemo {

    static func main() async throws {
        printSection("WatchlistStore + WorkspaceStore SQLite 持久化端到端 demo（第 11 个真数据 demo）")

        // 段 1：准备临时文件路径
        printSection("段 1 · 准备临时 SQLite 文件路径")
        let watchlistPath = NSTemporaryDirectory().appending("watchlist_demo_\(UUID().uuidString).sqlite")
        let workspacePath = NSTemporaryDirectory().appending("workspace_demo_\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(atPath: watchlistPath)
            try? FileManager.default.removeItem(atPath: workspacePath)
        }
        print("  📁 watchlist: \(watchlistPath)")
        print("  📁 workspace: \(workspacePath)")

        // 段 2：写入
        printSection("段 2 · 写入 WatchlistBook 3 组 + WorkspaceBook 3 模板")
        let watchlistOriginal = makeSampleWatchlistBook()
        let workspaceOriginal = makeSampleWorkspaceBook()

        let writeWatchlist = try SQLiteWatchlistBookStore(path: watchlistPath)
        try await writeWatchlist.save(watchlistOriginal)
        await writeWatchlist.close()
        print("  ✅ WatchlistBook 写入：\(watchlistOriginal.groups.count) 组 / \(watchlistOriginal.groups.flatMap(\.instrumentIDs).count) 合约")

        let writeWorkspace = try SQLiteWorkspaceBookStore(path: workspacePath)
        try await writeWorkspace.save(workspaceOriginal)
        await writeWorkspace.close()
        let activeID = workspaceOriginal.activeTemplateID
        let activeName = activeID.flatMap { id in workspaceOriginal.template(id: id)?.name } ?? "(无)"
        print("  ✅ WorkspaceBook 写入：\(workspaceOriginal.templates.count) 模板 · 激活 \(activeName)")

        // 段 3：模拟"进程重启" → 重新打开 → load 验证
        printSection("段 3 · 模拟进程重启 · 重新打开同 path → load 验证完整往返")
        let readWatchlist = try SQLiteWatchlistBookStore(path: watchlistPath)
        let watchlistLoaded = try await readWatchlist.load()
        await readWatchlist.close()
        let readWorkspace = try SQLiteWorkspaceBookStore(path: workspacePath)
        let workspaceLoaded = try await readWorkspace.load()
        await readWorkspace.close()

        let watchlistMatch = (watchlistLoaded == watchlistOriginal)
        let workspaceMatch = (workspaceLoaded == workspaceOriginal)
        print("  \(watchlistMatch ? "✅" : "❌") WatchlistBook load 完整往返：\(watchlistMatch)")
        print("  \(workspaceMatch ? "✅" : "❌") WorkspaceBook load 完整往返（含 templates / windows / shortcut / activeTemplateID）：\(workspaceMatch)")
        if let loaded = watchlistLoaded {
            print("  📋 Watchlist 恢复后分组：")
            for g in loaded.groups {
                print("     - \(g.name)（\(g.instrumentIDs.count) 合约）：\(g.instrumentIDs.joined(separator: " / "))")
            }
        }
        if let loaded = workspaceLoaded {
            print("  📋 Workspace 恢复后模板：")
            for t in loaded.templates {
                print("     - \(t.name)（\(t.kind.rawValue) · \(t.windows.count) 窗口）\(loaded.activeTemplateID == t.id ? " [激活]" : "")")
            }
        }

        // 段 4：文件大小内省
        printSection("段 4 · SQLite 文件大小内省")
        let watchlistSize = fileSize(watchlistPath)
        let workspaceSize = fileSize(workspacePath)
        print("  📦 watchlist.sqlite: \(watchlistSize) 字节")
        print("  📦 workspace.sqlite: \(workspaceSize) 字节")
        print("  💡 单本 Book JSON 整存模式 · UPSERT id=1 单例 · 数据规模 < 几 KB")

        // 段 5：负向场景 · 脏 JSON 触发 decodeFailed
        printSection("段 5 · 负向场景 · 脏 JSON 显式抛 decodeFailed")
        let corruptPath = NSTemporaryDirectory().appending("corrupt_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(atPath: corruptPath) }
        let corruptConn = try SQLiteConnection(path: corruptPath)
        try await corruptConn.exec("""
            CREATE TABLE IF NOT EXISTS watchlist_book (
              id INTEGER PRIMARY KEY CHECK(id = 1),
              data TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            );
            INSERT INTO watchlist_book (id, data, updated_at) VALUES (1, 'corrupt-not-json{{{', 0);
            """)
        let corruptStore = SQLiteWatchlistBookStore(connection: corruptConn)
        var didThrowDecodeFailed = false
        do {
            _ = try await corruptStore.load()
        } catch WatchlistBookStoreError.decodeFailed {
            didThrowDecodeFailed = true
        } catch {
            print("  ⚠️ 抛了非预期错：\(error)")
        }
        await corruptStore.close()
        print("  \(didThrowDecodeFailed ? "✅" : "❌") 脏 JSON load 抛 WatchlistBookStoreError.decodeFailed：\(didThrowDecodeFailed)")
        print("  💡 含义：UI 层 load 失败显式可感知 · 不会静默回退到空 Book 让用户丢数据")

        // 总结
        let allOK = watchlistMatch && workspaceMatch && didThrowDecodeFailed
        printSection(allOK
            ? "🎉 第 11 个真数据 demo 通过（WP-19a-5/6 持久化端到端 · UI 启动恢复 + 脏数据保护）"
            : "⚠️  部分验收未达标（详见上方）")
    }

    // MARK: - 样本数据构造

    static func makeSampleWatchlistBook() -> WatchlistBook {
        var book = WatchlistBook()
        let core = book.addGroup(name: "核心持仓")
        let backup = book.addGroup(name: "备选品种")
        let arb = book.addGroup(name: "套利对")
        for sym in ["RB0", "IF0", "AU0", "CU0"] { book.addInstrument(sym, to: core.id) }
        for sym in ["MA0", "TA0", "PP0"] { book.addInstrument(sym, to: backup.id) }
        for sym in ["RB-HC", "Y-P"] { book.addInstrument(sym, to: arb.id) }
        return book
    }

    static func makeSampleWorkspaceBook() -> WorkspaceBook {
        var book = WorkspaceBook()
        let pre = book.addTemplate(name: "盘前准备", kind: .preMarket)
        let inMkt = book.addTemplate(name: "盘中盯盘", kind: .inMarket)
        let post = book.addTemplate(name: "盘后复盘", kind: .postMarket)
        book.setActive(id: inMkt.id)

        // 给"盘中"模板加 2 个窗口
        var inMktTpl = book.template(id: inMkt.id)!
        inMktTpl.windows = [
            WindowLayout(
                instrumentID: "RB0", period: .minute1, indicatorIDs: [], drawingIDs: [],
                frame: LayoutFrame(x: 0, y: 0, width: 0.5, height: 1), zIndex: 0
            ),
            WindowLayout(
                instrumentID: "IF0", period: .minute5, indicatorIDs: [], drawingIDs: [],
                frame: LayoutFrame(x: 0.5, y: 0, width: 0.5, height: 1), zIndex: 0
            )
        ]
        book.updateTemplate(inMktTpl)
        // 给"盘前"快捷键 Cmd+1
        book.setShortcut(WorkspaceShortcut(keyCode: 18, modifierFlags: 1 << 20), for: pre.id)
        // 不加窗口的"盘后"也保留作模板对照
        _ = post
        return book
    }

    // MARK: - 工具

    static func fileSize(_ path: String) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int) ?? 0
    }

    static func printSection(_ title: String) {
        print("─────────────────────────────────────────────")
        print(title)
        print("─────────────────────────────────────────────")
    }
}
