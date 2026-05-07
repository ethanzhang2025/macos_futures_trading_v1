// SyncCore 模块入口测试 · WP-60 batch001

import Testing
@testable import SyncCore

@Suite("SyncCoreModule")
struct SyncCoreModuleTests {
    @Test("模块版本非空")
    func moduleVersion() {
        #expect(!SyncCoreModule.version.isEmpty)
    }
}
