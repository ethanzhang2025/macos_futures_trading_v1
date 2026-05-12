// v17.84 · InAppOverlayChannel 单测

import Testing
import Foundation
@testable import AlertCore

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

@Suite("InAppOverlayChannel · v17.84 NotificationCenter 桥")
struct InAppOverlayChannelTests {

    @Test("kind = .inApp")
    func kindIsInApp() {
        let channel = InAppOverlayChannel()
        #expect(channel.kind == .inApp)
    }

    @Test("send 后 NotificationCenter post NotificationEvent")
    func sendPostsEvent() async {
        let center = NotificationCenter()
        let name = Notification.Name("test.alertInApp.send1")
        let channel = InAppOverlayChannel(center: center, notificationName: name)
        let received = Box<NotificationEvent?>(nil)
        let token = center.addObserver(forName: name, object: nil, queue: nil) { note in
            received.value = note.object as? NotificationEvent
        }
        defer { center.removeObserver(token) }

        let event = NotificationEvent(
            alertID: UUID(),
            alertName: "rb 突破 3230",
            instrumentID: "rb2510",
            triggerPrice: 3230,
            triggeredAt: Date(),
            message: "current price 3231 > 3230"
        )
        await channel.send(event)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(received.value != nil)
        #expect(received.value?.alertID == event.alertID)
        #expect(received.value?.instrumentID == "rb2510")
    }

    @Test("默认 notificationName = .alertInAppOverlay")
    func defaultNotificationName() async {
        let center = NotificationCenter()
        let channel = InAppOverlayChannel(center: center)
        let counter = Box<Int>(0)
        let token = center.addObserver(forName: .alertInAppOverlay, object: nil, queue: nil) { _ in
            counter.value += 1
        }
        defer { center.removeObserver(token) }
        let event = NotificationEvent(
            alertID: UUID(), alertName: "A", instrumentID: "x", triggerPrice: 1,
            triggeredAt: Date(), message: "msg"
        )
        await channel.send(event)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(counter.value == 1)
    }
}
