import Testing
@testable import JournalCore

@Suite("JournalCore 模块骨架")
struct JournalCoreSkeletonTests {
    @Test("模块版本号非空")
    func versionNotEmpty() {
        #expect(!JournalCoreModule.version.isEmpty)
    }
}
