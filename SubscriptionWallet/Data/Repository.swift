import Foundation
import SwiftData
import Observation

enum WalletSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [StoredSubscription.self, StoredPreferences.self] }
    @Model final class StoredSubscription {
        var id: UUID
        var serviceID: String?
        var payload: Data
        init(_ value: Subscription) throws { id = value.id; serviceID = value.serviceID; payload = try JSONEncoder().encode(value) }
    }
    @Model final class StoredPreferences {
        var key: String
        var payload: Data
        init(_ value: Preferences) throws { key = "preferences"; payload = try JSONEncoder().encode(value) }
        init(key: String, payload: Data) { self.key = key; self.payload = payload }
    }
}
enum WalletMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [WalletSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
typealias StoredSubscription = WalletSchemaV1.StoredSubscription
typealias StoredPreferences = WalletSchemaV1.StoredPreferences

@MainActor @Observable final class WalletRepository {
    private let context: ModelContext
    private let commitContext: (ModelContext) throws -> Void
    var records: [Subscription] = []
    var preferences = Preferences()
    var checkup = CheckupState()
    var error: String?
    let catalog: [CatalogItem]
    init(container: ModelContainer, commit: @escaping (ModelContext) throws -> Void = { try $0.save() }) throws {
        commitContext = commit
        context = ModelContext(container); context.autosaveEnabled = false
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else { throw WalletError.storage("服务目录缺失，无法启动。") }
        catalog = try JSONDecoder().decode([CatalogItem].self, from: Data(contentsOf: url))
        try reload()
    }
    func reload() throws {
        let values = try context.fetch(FetchDescriptor<StoredSubscription>()).map { try JSONDecoder().decode(Subscription.self, from: $0.payload) }
        let stored = try context.fetch(FetchDescriptor<StoredPreferences>())
        let settings = try stored.first(where: { $0.key == "preferences" }).map { try JSONDecoder().decode(Preferences.self, from: $0.payload) } ?? Preferences()
        let state = try stored.first(where: { $0.key == "checkup" }).map { try JSONDecoder().decode(CheckupState.self, from: $0.payload) } ?? CheckupState()
        records = values; preferences = settings; checkup = state
    }
    func existing(serviceID: String) -> Subscription? { records.first { $0.serviceID == serviceID } }
    func save(_ input: Subscription) throws {
        do {
            var s = input; s.name = s.name.trimmingCharacters(in: .whitespacesAndNewlines); s.updatedAt = Date()
            let entities = try context.fetch(FetchDescriptor<StoredSubscription>())
            if let sid = s.serviceID, let duplicate = entities.first(where: { $0.serviceID == sid && $0.id != s.id }) { throw WalletError.duplicate(duplicate.id) }
            try Validator.validate(s, all: records)
            if let parent = s.sourceSubscriptionID, let name = records.first(where: { $0.id == parent })?.name { s.sourceName = name }
            if let previous = records.first(where: { $0.id == s.id }), previous.acquisition == .paid && s.acquisition != .paid { try detachChildren(of: previous, entities: entities) }
            if let entity = entities.first(where: { $0.id == s.id }) { entity.serviceID = s.serviceID; entity.payload = try JSONEncoder().encode(s) }
            else { context.insert(try StoredSubscription(s)) }
            try commitContext(context); try reload()
        } catch { context.rollback(); throw error }
    }
    private func detachChildren(of parent: Subscription, entities: [StoredSubscription]) throws {
        for entity in entities {
            var child = try JSONDecoder().decode(Subscription.self, from: entity.payload)
            if child.sourceSubscriptionID == parent.id { child.sourceSubscriptionID = nil; if child.sourceName.isEmpty { child.sourceName = parent.name }; child.updatedAt = Date(); entity.payload = try JSONEncoder().encode(child) }
        }
    }
    func delete(_ s: Subscription) throws {
        do {
            let entities = try context.fetch(FetchDescriptor<StoredSubscription>())
            try detachChildren(of: s, entities: entities)
            entities.filter { $0.id == s.id }.forEach { context.delete($0) }
            try commitContext(context); try reload()
        } catch { context.rollback(); throw error }
    }
    func setArchived(_ s: Subscription, _ archived: Bool) throws { var v = s; v.isArchived = archived; try save(v) }
    func saveWalletOrder(_ ids: [UUID]) throws { var p = preferences; p.walletOrder = ids; try savePreferences(p) }
    func savePreferences(_ p: Preferences) throws {
        do {
            for (_, raw) in p.exchangeRates { _ = try Money.rate(raw) }
            let data = try JSONEncoder().encode(p)
            if let e = try context.fetch(FetchDescriptor<StoredPreferences>()).first(where: { $0.key == "preferences" }) { e.payload = data } else { context.insert(try StoredPreferences(p)) }
            try commitContext(context); try reload()
        } catch { context.rollback(); throw error }
    }
    func restore(_ backup: ValidatedBackup) throws {
        _ = try BackupCodec.validate(backup.envelope)
        try replaceAll(records: backup.envelope.subscriptions, preferences: backup.envelope.preferences, checkup: backup.envelope.checkup ?? CheckupState())
    }
    func clearAll() throws { try replaceAll(records: [], preferences: Preferences()) }
    func replaceAll(records newRecords: [Subscription], preferences newPreferences: Preferences, checkup newCheckup: CheckupState = CheckupState()) throws {
        // Encode and fetch before modifying the context. Publish UI state only after the single commit.
        let replacement = try newRecords.map(StoredSubscription.init)
        let replacementPreferences = try StoredPreferences(newPreferences)
        let replacementCheckup = StoredPreferences(key: "checkup", payload: try JSONEncoder().encode(newCheckup))
        do {
            let existing = try context.fetch(FetchDescriptor<StoredSubscription>())
            let existingPreferences = try context.fetch(FetchDescriptor<StoredPreferences>())
            for entity in existing { context.delete(entity) }
            for entity in existingPreferences { context.delete(entity) }
            for entity in replacement { context.insert(entity) }
            context.insert(replacementPreferences); context.insert(replacementCheckup)
            try commitContext(context)
            records = newRecords; preferences = newPreferences; checkup = newCheckup
        } catch { context.rollback(); throw error }
    }
    static func container(inMemory: Bool = false, storeURL: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: WalletSchemaV1.self)
        let config = storeURL.map { ModelConfiguration(schema: schema, url: $0, cloudKitDatabase: .none) } ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: WalletMigrationPlan.self, configurations: [config])
    }
}


extension WalletRepository {
    private func saveCheckup(_ state: CheckupState) throws {
        let data = try JSONEncoder().encode(state)
        do {
            if let entity = try context.fetch(FetchDescriptor<StoredPreferences>()).first(where: { $0.key == "checkup" }) { entity.payload = data }
            else { context.insert(StoredPreferences(key: "checkup", payload: data)) }
            try commitContext(context); checkup = state
        } catch { context.rollback(); throw error }
    }
    func startCheckup(excluding: Set<String> = []) throws {
        guard checkup.session?.status != .draft else { return }
        var state = checkup; state.session = try CheckupEngine.start(catalog: catalog, excluding: excluding); try saveCheckup(state)
    }
    func answerCheckup(choice: CheckupChoice, member: Subscription? = nil) throws {
        guard let session = checkup.session, let id = session.currentServiceID else { throw WalletError.invalid("请先开始体检。") }
        let existing = records.first { $0.serviceID == id }
        let answer = CheckupAnswer(serviceID: id, choice: choice, member: member, baseID: existing?.id, baseUpdatedAt: existing?.updatedAt)
        if choice.hasMembership {
            guard let member, member.serviceID == id else { throw WalletError.invalid("会员资料与题目不一致。") }
            guard choice == .paid ? member.acquisition == .paid : [.bundled, .gifted].contains(member.acquisition) else { throw WalletError.invalid("回答与会员来源不一致。") }
            try Validator.validate(member, all: records)
        } else if member != nil { throw WalletError.invalid("没有或不确定的回答不应包含会员资料。") }
        var state = checkup; state.session = try CheckupEngine.answering(session, answer: answer, catalog: catalog); try saveCheckup(state)
    }
    func previousCheckupCard() throws {
        guard var session = checkup.session, session.status == .draft, session.currentIndex > 0 else { return }
        session.currentIndex -= 1; session.updatedAt = Date()
        var state = checkup; state.session = session; try saveCheckup(state)
    }
    func revisitCheckupCard(serviceID: String) throws {
        guard var session = checkup.session, session.status == .draft, let index = session.queue.firstIndex(of: serviceID) else { return }
        session.currentIndex = index; session.updatedAt = Date()
        var state = checkup; state.session = session; try saveCheckup(state)
    }
    func selectCheckupArchive(serviceID: String, selected: Bool) throws {
        guard var session = checkup.session, session.status == .draft, session.answers.contains(where: { $0.serviceID == serviceID && $0.choice == .none }) else { return }
        session.archiveServiceIDs.removeAll { $0 == serviceID }
        if selected { session.archiveServiceIDs.append(serviceID) }
        var state = checkup; state.session = session; try saveCheckup(state)
    }
    func discardCheckup() throws {
        var state = checkup; state.session = nil; try saveCheckup(state)
    }
    func resolvePending(serviceID: String) throws {
        var state = checkup; state.pending.removeAll { $0.serviceID == serviceID }; try saveCheckup(state)
    }
    func checkupPlan(now: Date = Date()) throws -> CheckupPlan {
        guard let session = checkup.session else { throw WalletError.invalid("没有待提交的体检。") }
        return try CheckupEngine.plan(session: session, records: records, pending: checkup.pending, catalog: catalog, preferences: preferences, now: now)
    }
    @discardableResult func commitCheckup(sessionID: UUID, now: Date = Date()) throws -> Bool {
        if checkup.committedSessionIDs.contains(sessionID) { return false }
        guard var session = checkup.session, session.id == sessionID else { throw WalletError.invalid("体检已变化，未提交。") }
        let plan = try checkupPlan(now: now)
        session.status = .completed; session.updatedAt = now
        var state = checkup; state.session = nil; state.pending = plan.pending; state.latest = plan.result; state.committedSessionIDs.append(sessionID)
        // Subscription changes, pending list, latest result and idempotency key share ONE save.
        try replaceAll(records: plan.records, preferences: preferences, checkup: state)
        return true
    }
}
