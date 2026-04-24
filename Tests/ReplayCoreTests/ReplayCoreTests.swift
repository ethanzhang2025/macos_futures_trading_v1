import Testing
@testable import ReplayCore

@Suite("ReplayCore 模块骨架")
struct ReplayCoreSkeletonTests {
    @Test("模块版本号非空")
    func versionNotEmpty() {
        #expect(!ReplayCoreModule.version.isEmpty)
    }
}
