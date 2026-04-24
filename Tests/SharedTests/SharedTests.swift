import Testing
@testable import Shared

@Suite("Shared 模块骨架")
struct SharedSkeletonTests {
    @Test("模块版本号非空")
    func versionNotEmpty() {
        #expect(!SharedModule.version.isEmpty)
    }
}
