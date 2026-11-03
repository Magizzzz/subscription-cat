import XCTest
import UserNotifications
@testable import SubscriptionWallet

@MainActor final class FakeNotifications: NotificationClient {
    var permission: UNAuthorizationStatus = .authorized
    var pending: [UNNotificationRequest] = []
    var fails = false
    var silentlyDrops = false
    var requestsPermission = 0
    var deliveredClears = 0
    func removeAllDeliveredNotifications() { deliveredClears += 1 }
    func permissionStatus() async -> UNAuthorizationStatus { permission }
    func askPermission() async throws { requestsPermission += 1 }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { pending }
    func add(_ request: UNNotificationRequest) async throws {
        if fails { throw WalletError.storage("模拟系统添加失败") }
        if !silentlyDrops { pending.removeAll { $0.identifier == request.identifier }; pending.append(request) }
    }
    func removePendingNotificationRequests(withIdentifiers ids: [String]) { pending.removeAll { ids.contains($0.identifier) } }
}
@MainActor final class NotificationCoordinatorTests: XCTestCase {
    let now=LocalDate("2026-10-17")!.at(hour:10)
    func member() -> Subscription { var s=Subscription();s.name="测试会员";s.category = .other;s.nextChargeOn="2026-11-01";s.reminderEnabled=true;return s }
    func testN07DeniedPreservesIntentNoScheduledSuccess() async {
        let client=FakeNotifications();client.permission = .denied;let coordinator=NotificationCoordinator(client:client);let s=member()
        await coordinator.reconcile([s],preferences:Preferences(),now:now)
        XCTAssertEqual(coordinator.states[s.id],"系统通知已关闭");XCTAssertEqual(coordinator.scheduledCount,0);XCTAssertTrue(s.reminderEnabled);XCTAssertEqual(client.requestsPermission,0)
    }
    func testN08PermissionChangedAndReconciled() async {
        let client=FakeNotifications();client.permission = .denied;let c=NotificationCoordinator(client:client);let s=member();await c.reconcile([s],preferences:Preferences(),now:now)
        client.permission = .authorized;await c.reconcile([s],preferences:Preferences(),now:now);XCTAssertEqual(c.states[s.id],"已安排");XCTAssertEqual(client.pending.count,1)
    }
    func testN09ArchiveAndDeletionCancelRequests() async {
        let client=FakeNotifications();let c=NotificationCoordinator(client:client);var s=member();await c.reconcile([s],preferences:Preferences(),now:now);let previous=client.pending[0].identifier
        s.nextChargeOn="2026-12-01";s.updatedAt=Date();await c.reconcile([s],preferences:Preferences(),changedIDs:[s.id],now:now);XCTAssertFalse(client.pending.contains { $0.identifier==previous })
        s.isArchived=true;await c.reconcile([s],preferences:Preferences(),changedIDs:[s.id],now:now);XCTAssertTrue(client.pending.isEmpty)
        await c.reconcile([],preferences:Preferences(),now:now);XCTAssertTrue(client.pending.isEmpty)
    }
    func testN20FailureNotMarkedScheduled() async {
        let client=FakeNotifications();client.fails=true;let c=NotificationCoordinator(client:client);let s=member();await c.reconcile([s],preferences:Preferences(),now:now);XCTAssertEqual(c.states[s.id],"暂未安排，请重试");XCTAssertEqual(c.scheduledCount,0)
    }
    func testPendingVerificationDetectsDroppedRequest() async {
        let client=FakeNotifications();client.silentlyDrops=true;let c=NotificationCoordinator(client:client);let s=member();await c.reconcile([s],preferences:Preferences(),now:now);XCTAssertEqual(c.states[s.id],"暂未安排，请重试")
    }
    func testCatchupSurvivesForegroundButNotChangedRecord() async {
        let client=FakeNotifications();let c=NotificationCoordinator(client:client);var s=member();s.nextChargeOn="2026-10-17";await c.reconcile([s],preferences:Preferences(),changedIDs:[s.id],now:Date());
        // Use an actual future trigger so UNCalendarNotificationTrigger.nextTriggerDate is deterministic relative to system time.
        let actual=Date();s.nextChargeOn=LocalDate(date:actual).description
        await c.reconcile([s],preferences:Preferences(),changedIDs:[s.id],now:LocalDate(date:actual).at(hour:23))
        // Main preservation behavior is checked at a business clock later than 09:00.
        let initialCount=client.pending.count
        await c.reconcile([s],preferences:Preferences(),now:LocalDate(date:actual).at(hour:23))
        XCTAssertEqual(client.pending.count,initialCount)
        s.isArchived=true;await c.reconcile([s],preferences:Preferences(),changedIDs:[s.id],now:actual);XCTAssertTrue(client.pending.isEmpty)
    }
    func testNearestCatchupKeepsBudgetSlotAcrossForeground() async {
        let client = FakeNotifications()
        // Future business clock keeps calendar triggers independent of the test machine's hour.
        let clock = LocalDate(date: Date()).adding(days: 1).at(hour: 10)
        let coordinator = NotificationCoordinator(client: client)
        var urgent = member()
        urgent.nextChargeOn = LocalDate(date: clock).description
        urgent.reminderLeadDays = 0
        await coordinator.reconcile([urgent], preferences: Preferences(), changedIDs: [urgent.id], now: clock)
        let urgentRequest = client.pending.first!.identifier
        let later = (1...60).map { offset -> Subscription in
            var s = member()
            s.nextChargeOn = LocalDate(date: clock).adding(days: offset).description
            s.reminderLeadDays = 0
            return s
        }
        await coordinator.reconcile([urgent] + later, preferences: Preferences(), now: clock)
        XCTAssertEqual(client.pending.count, 60)
        XCTAssertTrue(client.pending.contains { $0.identifier == urgentRequest })
        XCTAssertEqual(coordinator.states[urgent.id], "已安排")
        XCTAssertTrue(coordinator.outsideBudget.contains(later.last!.id))
        XCTAssertEqual(coordinator.states[later.last!.id], "超出近期预算，打开 App 时补齐")
    }
    func testPreservedCatchupAddFailureReportsRetry() async {
        let client = FakeNotifications()
        let c = NotificationCoordinator(client: client)
        let clock = LocalDate(date: Date()).adding(days: 1).at(hour: 10)
        var s = member(); s.nextChargeOn = LocalDate(date: clock).description
        await c.reconcile([s], preferences: Preferences(), changedIDs: [s.id], now: clock)
        XCTAssertEqual(client.pending.count, 1)
        client.fails = true
        await c.reconcile([s], preferences: Preferences(), now: clock)
        XCTAssertEqual(c.states[s.id], "暂未安排，请重试")
        XCTAssertEqual(c.scheduledCount, 0)
    }

}
