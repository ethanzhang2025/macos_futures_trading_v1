// AlertCore Linux 通道 v1 测试 · ConsoleChannel + FileChannel + Dispatcher 集成

import Testing
import Foundation
@testable import AlertCore

private let fixedDate = Date(timeIntervalSince1970: 1_745_500_000)  // 2025-04-24 19:46:40 UTC

private func makeEvent(name: String = "RB0 涨破 3200") -> NotificationEvent {
    NotificationEvent(
        alertID: UUID(),
        alertName: name,
        instrumentID: "RB0",
        triggerPrice: Decimal(3220),
        triggeredAt: fixedDate,
        message: "价格 3220 高于 3200"
    )
}

/// 测试用收集器（替代 print stdout）
private actor LineCollector {
    private(set) var lines: [String] = []
    func append(_ s: String) { lines.append(s) }
}

// MARK: - ConsoleChannel

@Suite("ConsoleChannel · 协议合约")
struct ConsoleChannelTests {

    @Test("kind = .console")
    func kindIsConsole() {
        let channel = ConsoleChannel()
        #expect(channel.kind == .console)
    }

    @Test("writer 注入 + 默认前缀 + 注入时间戳")
    func writerInjectionWithFixedTimestamp() async {
        let collector = LineCollector()
        let channel = ConsoleChannel(
            prefix: "[TEST]",
            timestampFormatter: { _ in "2025-04-24 19:46:40" },
            writer: { line in Task { await collector.append(line) } }
        )
        await channel.send(makeEvent())
        try? await Task.sleep(nanoseconds: 50_000_000)
        let lines = await collector.lines
        #expect(lines.count == 1)
        #expect(lines[0] == "[TEST] [2025-04-24 19:46:40] 🔔 RB0 涨破 3200 · RB0 @ 3220 · 价格 3220 高于 3200")
    }

    @Test("不同前缀互不干扰")
    func multiplePrefixes() async {
        let collector1 = LineCollector()
        let collector2 = LineCollector()
        let ch1 = ConsoleChannel(prefix: "[A]", timestampFormatter: { _ in "T" },
                                  writer: { line in Task { await collector1.append(line) } })
        let ch2 = ConsoleChannel(prefix: "[B]", timestampFormatter: { _ in "T" },
                                  writer: { line in Task { await collector2.append(line) } })
        await ch1.send(makeEvent())
        await ch2.send(makeEvent())
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(await collector1.lines.first?.hasPrefix("[A]") == true)
        #expect(await collector2.lines.first?.hasPrefix("[B]") == true)
    }
}

// MARK: - FileChannel

@Suite("FileChannel · 协议合约")
struct FileChannelTests {

    private static func tempPath() -> String {
        NSTemporaryDirectory().appending("alert_file_channel_\(UUID().uuidString).log")
    }

    @Test("kind = .file")
    func kindIsFile() throws {
        let channel = try FileChannel(path: Self.tempPath())
        #expect(channel.kind == .file)
    }

    @Test("写一条 + 读回内容")
    func writeOneLineAndReadBack() async throws {
        let path = Self.tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let channel = try FileChannel(path: path, timestampFormatter: { _ in "2025-04-24 19:46:40" })
        await channel.send(makeEvent())
        await channel.close()

        let content = try String(contentsOfFile: path, encoding: .utf8)
        #expect(content == "[2025-04-24 19:46:40] RB0 涨破 3200 | RB0 | @ 3220 | 价格 3220 高于 3200\n")
    }

    @Test("多次追加 · 顺序保留 + 不覆盖")
    func multipleAppendsPreserveOrder() async throws {
        let path = Self.tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let channel = try FileChannel(path: path, timestampFormatter: { _ in "T" })
        await channel.send(makeEvent(name: "A"))
        await channel.send(makeEvent(name: "B"))
        await channel.send(makeEvent(name: "C"))
        await channel.close()

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.split(separator: "\n").map(String.init)
        #expect(lines.count == 3)
        // 行格式："[T] {alertName} | {instrumentID} | @ {price} | {message}"
        #expect(lines[0].hasPrefix("[T] A |"))
        #expect(lines[1].hasPrefix("[T] B |"))
        #expect(lines[2].hasPrefix("[T] C |"))
    }

    @Test("close 后 send 静默 noop · 不抛错")
    func sendAfterCloseIsNoop() async throws {
        let path = Self.tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let channel = try FileChannel(path: path, timestampFormatter: { _ in "T" })
        await channel.send(makeEvent(name: "before-close"))
        await channel.close()
        await channel.send(makeEvent(name: "after-close"))  // 应静默忽略

        let content = try String(contentsOfFile: path, encoding: .utf8)
        #expect(content.contains("before-close"))
        #expect(!content.contains("after-close"))
    }

    @Test("跨实例追加：同一文件第二次打开 → 不清空原内容")
    func reopenAppendsRatherThanTruncates() async throws {
        let path = Self.tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let ch1 = try FileChannel(path: path, timestampFormatter: { _ in "T" })
        await ch1.send(makeEvent(name: "first"))
        await ch1.close()

        let ch2 = try FileChannel(path: path, timestampFormatter: { _ in "T" })
        await ch2.send(makeEvent(name: "second"))
        await ch2.close()

        let content = try String(contentsOfFile: path, encoding: .utf8)
        #expect(content.contains("first"))
        #expect(content.contains("second"))
    }
}

// MARK: - Dispatcher 集成 · 多 kind 广播

@Suite("NotificationDispatcher · Console + File 集成")
struct DispatcherChannelsIntegrationTests {

    @Test("注册 console + file · dispatch 同时分发到两通道")
    func dispatchToBothChannels() async throws {
        let collector = LineCollector()
        let console = ConsoleChannel(
            prefix: "[X]",
            timestampFormatter: { _ in "T" },
            writer: { line in Task { await collector.append(line) } }
        )
        let path = NSTemporaryDirectory().appending("dispatcher_test_\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let file = try FileChannel(path: path, timestampFormatter: { _ in "T" })

        let dispatcher = NotificationDispatcher()
        await dispatcher.register(console)
        await dispatcher.register(file)
        let kinds = await dispatcher.registeredKinds()
        #expect(kinds == [.console, .file])

        await dispatcher.dispatch(makeEvent(name: "ALL"), to: [.console, .file])
        await file.close()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let lines = await collector.lines
        #expect(lines.count == 1)
        #expect(lines[0].contains("ALL"))

        let fileContent = try String(contentsOfFile: path, encoding: .utf8)
        #expect(fileContent.contains("ALL"))
    }

    @Test("dispatch to 子集 → 仅命中通道收到事件")
    func dispatchToSubsetSkipsOthers() async throws {
        let collector = LineCollector()
        let console = ConsoleChannel(
            prefix: "[X]",
            timestampFormatter: { _ in "T" },
            writer: { line in Task { await collector.append(line) } }
        )
        let path = NSTemporaryDirectory().appending("subset_test_\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let file = try FileChannel(path: path, timestampFormatter: { _ in "T" })

        let dispatcher = NotificationDispatcher()
        await dispatcher.register(console)
        await dispatcher.register(file)
        await dispatcher.dispatch(makeEvent(name: "ONLY-CONSOLE"), to: [.console])
        await file.close()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(await collector.lines.count == 1)
        let fileContent = try String(contentsOfFile: path, encoding: .utf8)
        #expect(!fileContent.contains("ONLY-CONSOLE"))  // file 通道未命中
    }
}

// MARK: - NotificationChannelKind 扩展

@Suite("NotificationChannelKind · WP-52 v1 扩展（console + file）")
struct NotificationChannelKindExtensionTests {

    @Test("CaseIterable 包含 6 种")
    func allCasesIncludesNew() {
        let all = Set(NotificationChannelKind.allCases)
        #expect(all == [.inApp, .systemNotice, .sound, .console, .file, .webhook])
    }

    @Test("rawValue 与 case 对齐（向后兼容旧 JSON）")
    func rawValuesMatchCaseNames() {
        #expect(NotificationChannelKind.console.rawValue == "console")
        #expect(NotificationChannelKind.file.rawValue == "file")
        #expect(NotificationChannelKind.webhook.rawValue == "webhook")
        // 旧值仍可解码
        #expect(NotificationChannelKind(rawValue: "inApp") == .inApp)
        #expect(NotificationChannelKind(rawValue: "systemNotice") == .systemNotice)
        #expect(NotificationChannelKind(rawValue: "sound") == .sound)
    }
}

// MARK: - WebhookChannel (v17.32 B3)

/// Mock HTTP 客户端 · 拦截 request 不联网 · 记录调用参数
private actor MockWebhookClient: WebhookHTTPClient {
    private(set) var calls: [(url: URL, headers: [String: String], body: Data)] = []
    private let response: (statusCode: Int, body: Data)?

    init(response: (statusCode: Int, body: Data)? = (200, Data())) {
        self.response = response
    }

    func post(url: URL, headers: [String: String], body: Data, timeout: TimeInterval) async -> (statusCode: Int, body: Data)? {
        calls.append((url, headers, body))
        return response
    }
}

@Suite("WebhookChannel · v17.32 B3 通用 JSON POST")
struct WebhookChannelTests {

    @Test("kind = .webhook")
    func kindIsWebhook() {
        let channel = WebhookChannel(url: URL(string: "https://example.com/hook")!)
        #expect(channel.kind == .webhook)
    }

    @Test("send · POST JSON 含 alert_name / instrument_id / trigger_price / message")
    func sendPostsExpectedJson() async throws {
        let mock = MockWebhookClient(response: (200, Data()))
        let channel = WebhookChannel(
            url: URL(string: "https://example.com/hook")!,
            headers: ["X-Custom": "abc"],
            client: mock,
            timestampFormatter: { _ in "2025-04-24T19:46:40Z" }
        )
        await channel.send(makeEvent(name: "RB0 突破"))
        let calls = await mock.calls
        #expect(calls.count == 1)
        let call = try #require(calls.first)
        #expect(call.url.absoluteString == "https://example.com/hook")
        #expect(call.headers["X-Custom"] == "abc")
        let json = try #require(try JSONSerialization.jsonObject(with: call.body) as? [String: Any])
        #expect(json["alert_name"] as? String == "RB0 突破")
        #expect(json["instrument_id"] as? String == "RB0")
        #expect(json["trigger_price"] as? String == "3220")
        #expect(json["message"] as? String == "价格 3220 高于 3200")
        #expect(json["triggered_at"] as? String == "2025-04-24T19:46:40Z")
        let success = await channel.lastDeliverySuccess
        #expect(success == true)
    }

    @Test("send · 非 2xx 标记失败（4xx · 5xx · 传输失败均失败）")
    func sendMarksFailureForNon2xx() async {
        let badStatus = MockWebhookClient(response: (404, Data()))
        let ch1 = WebhookChannel(url: URL(string: "https://x.test")!, client: badStatus)
        await ch1.send(makeEvent())
        #expect(await ch1.lastDeliverySuccess == false)

        let transportFail = MockWebhookClient(response: nil)
        let ch2 = WebhookChannel(url: URL(string: "https://x.test")!, client: transportFail)
        await ch2.send(makeEvent())
        #expect(await ch2.lastDeliverySuccess == false)
    }

    @Test("dispatcher 集成 · webhook 与其他 channel 互不影响")
    func integratesWithDispatcher() async {
        let mock = MockWebhookClient(response: (200, Data()))
        let webhook = WebhookChannel(url: URL(string: "https://x.test")!, client: mock)
        let collector = LineCollector()
        let console = ConsoleChannel(
            prefix: "[T]",
            timestampFormatter: { _ in "T" },
            writer: { line in Task { await collector.append(line) } }
        )
        let dispatcher = NotificationDispatcher(channels: [webhook, console])

        await dispatcher.dispatch(makeEvent(), to: [.webhook])
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(await mock.calls.count == 1)
        #expect(await collector.lines.isEmpty)  // console 不应被命中
    }
}
