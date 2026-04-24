import Testing
@testable import WorkspaceCore

@Suite("WorkspaceCore 模块骨架")
struct WorkspaceCoreSkeletonTests {
    @Test("模块版本号非空")
    func versionNotEmpty() {
        #expect(!WorkspaceCoreModule.version.isEmpty)
    }
}
