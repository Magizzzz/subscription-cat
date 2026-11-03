import Foundation
import UserNotifications
import Observation

@MainActor protocol NotificationClient {
    func permissionStatus() async -> UNAuthorizationStatus
    func removeAllDeliveredNotifications()
    func askPermission() async throws
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers: [String])
}
@MainActor struct SystemNotificationClient: NotificationClient {
    let center = UNUserNotificationCenter.current()
    func permissionStatus() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func removeAllDeliveredNotifications() { center.removeAllDeliveredNotifications() }
    func askPermission() async throws { _ = try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { await center.pendingNotificationRequests() }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func removePendingNotificationRequests(withIdentifiers ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
}

@MainActor @Observable final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    var authorization: UNAuthorizationStatus = .notDetermined
    var scheduledCount = 0
    var states: [UUID: String] = [:]
    var outsideBudget: Set<UUID> = []
    var routeID: UUID?
    var showReminderCenter = false
    var removedRecordNotice = false
    private var generation = 0
    private let center: any NotificationClient
    private var tail: Task<Void, Never>?
    init(client: (any NotificationClient)? = nil) {
        center = client ?? SystemNotificationClient()
        super.init()
        if client == nil { UNUserNotificationCenter.current().delegate = self }
    }
    var permissionLabel: String {
        switch authorization { case .notDetermined: "开启通知后，可接收系统提醒"; case .denied: "系统通知已关闭"; case .authorized, .provisional, .ephemeral: "系统通知已授权"; @unknown default: "通知状态待核对" }
    }
    var allowed: Bool { [.authorized, .provisional, .ephemeral].contains(authorization) }
    func requestPermission() async { try? await center.askPermission(); authorization = await center.permissionStatus() }
    func reconcile(_ records: [Subscription], preferences: Preferences, changedIDs: Set<UUID> = [], now: Date = Date()) async {
        let previous = tail
        let job = Task { @MainActor in
            await previous?.value
            await performReconciliation(records, preferences: preferences, changedIDs: changedIDs, now: now)
        }
        tail = job
        await job.value
    }
    func reconcileAfterRestore(_ records: [Subscription], preferences: Preferences, now: Date = Date()) async {
        let previous = tail
        let job = Task { @MainActor in
            await previous?.value
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
            center.removeAllDeliveredNotifications()
            await performReconciliation(records, preferences: preferences, changedIDs: [], now: now)
        }
        tail = job; await job.value
    }
    func clearAll() async {
        let previous = tail
        let job = Task { @MainActor in
            await previous?.value
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
            center.removeAllDeliveredNotifications()
            states = [:]; outsideBudget = []; scheduledCount = 0
            routeID = nil; showReminderCenter = false; removedRecordNotice = false
            authorization = await center.permissionStatus()
        }
        tail = job; await job.value
    }
    private func performReconciliation(_ records: [Subscription], preferences: Preferences, changedIDs: Set<UUID>, now: Date) async {
        generation += 1; let token = generation
        authorization = await center.permissionStatus()
        guard token == generation else { return }
        let plan = NotificationPlanner.plan(records, now: now, changedIDs: changedIDs)
        let pending = await center.pendingNotificationRequests()
        guard token == generation else { return }
        // Keep still-pending catch-up requests across foreground reconciliation; remove them immediately if their data changed.
        let desiredIDs = Set(plan.requests.map(\.id))
        let preserved = pending.filter { request in
            guard !desiredIDs.contains(request.identifier), let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let fire = trigger.nextTriggerDate(), fire > now,
                  let strings = request.content.userInfo["ids"] as? [String] else { return false }
            return strings.allSatisfy { raw in
                guard let id = UUID(uuidString: raw), !changedIDs.contains(id), let s = records.first(where: { $0.id == id }), s.reminderEnabled, StatusResolver.status(s, today: LocalDate(date: now)).held,
                      let event = EventResolver.event(s), event.date >= LocalDate(date: now) else { return false }
                return request.content.userInfo["fingerprint"] as? String == fingerprint(strings.compactMap { str in records.first { $0.id.uuidString == str } }, preferences)
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
        states = [:]; outsideBudget = plan.outsideBudget; scheduledCount = 0
        for s in records where !s.isArchived {
            states[s.id] = !s.hasDate ? "待补可用日期" : !s.reminderEnabled ? "未开启提醒" : !allowed ? (authorization == .denied ? "系统通知已关闭" : "等待通知授权") : "无未来提醒，待核对"
        }
        guard allowed else { return }
        var requested: [String: [UUID]] = [:]
        // Catch-up requests compete by fire time with regular requests. Reserving only
        // leftover slots could discard tomorrow's reminder in favor of months-away ones.
        let candidates = preserved.compactMap { request -> (String, Date)? in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger, let fire = trigger.nextTriggerDate() else { return nil }
            return (request.identifier, fire)
        }
            + plan.requests.map { ($0.id, $0.triggerAt) }
        let selectedIDs = Set(candidates.sorted {
            $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1
        }.prefix(60).map { $0.0 })
        let reserved = preserved.filter { selectedIDs.contains($0.identifier) }
        for request in preserved where !selectedIDs.contains(request.identifier) {
            outsideBudget.formUnion((request.content.userInfo["ids"] as? [String] ?? []).compactMap(UUID.init(uuidString:)))
        }
        for p in plan.requests where !selectedIDs.contains(p.id) {
            outsideBudget.formUnion(p.events.map(\.subscriptionID))
        }
        for request in reserved {
            let ids = (request.content.userInfo["ids"] as? [String] ?? []).compactMap(UUID.init(uuidString:))
            do { try await center.add(request); requested[request.identifier] = ids }
            catch { for id in ids { states[id] = "暂未安排，请重试" } }
        }
        for p in plan.requests where selectedIDs.contains(p.id) {
            guard token == generation else { return }
            let content = UNMutableNotificationContent(); content.title = "会员提醒"; content.body = NotificationPlanner.body(p, showNames: preferences.notificationShowsServiceName); content.sound = .default
            let ids = Array(Set(p.events.map(\.subscriptionID)))
            content.userInfo = ["ids": ids.map(\.uuidString), "fingerprint": fingerprint(records.filter { ids.contains($0.id) }, preferences)]
            var dc = LocalDate.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: p.triggerAt); dc.timeZone = LocalDate.calendar.timeZone
            do { try await center.add(UNNotificationRequest(identifier: p.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: false))); requested[p.id] = ids }
            catch { for id in ids { states[id] = "暂未安排，请重试" } }
        }
        let actual = Set(await center.pendingNotificationRequests().map(\.identifier))
        guard token == generation else { return }
        scheduledCount = actual.count
        for (id, members) in requested {
            for member in members where states[member] != "暂未安排，请重试" { states[member] = actual.contains(id) ? "已安排" : "暂未安排，请重试" }
        }
        for id in outsideBudget { states[id] = states[id] == "已安排" ? "已安排较近提醒，部分待补齐" : "超出近期预算，打开 App 时补齐" }
    }
    private func fingerprint(_ s: [Subscription], _ p: Preferences) -> String {
        s.sorted { $0.id.uuidString < $1.id.uuidString }.map { "\($0.id)|\($0.updatedAt.timeIntervalSince1970)" }.joined(separator: ",") + "|\(p.notificationShowsServiceName)"
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound, .list] }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let ids = response.notification.request.content.userInfo["ids"] as? [String] ?? []
        await MainActor.run { if ids.count == 1 { self.routeID = UUID(uuidString: ids[0]) } else { self.showReminderCenter = true } }
    }
}
