import XCTest
import SwiftData
@testable import SubscriptionWallet

@MainActor final class CheckupTests: XCTestCase {
    let now = LocalDate("2026-10-17")!.at()
    func repository() throws -> WalletRepository { try WalletRepository(container: WalletRepository.container(inMemory: true)) }
    func seed(_ id: String, _ repo: WalletRepository) -> Subscription {
        let item = repo.catalog.first { $0.id == id }!
        var value = Subscription(); value.serviceID = id; value.name = item.name; value.categoryRaw = item.category
        return value
    }
    func finish(_ repo: WalletRepository, first: CheckupChoice = .paid, unsure: Bool = false) throws {
        if repo.checkup.session == nil { try repo.startCheckup() }
        while let session = repo.checkup.session, let id = session.currentServiceID {
            if session.currentIndex == 0 && first.hasMembership {
                var value = repo.existing(serviceID: id) ?? seed(id, repo)
                if first == .benefit { value.acquisition = .bundled; value.amountMinor = nil; value.cycle = .unknown; value.autoRenew = .unknown; value.nextChargeOn = nil; value.recurrenceAnchorOn = nil }
                try repo.answerCheckup(choice: first, member: value)
            } else { try repo.answerCheckup(choice: session.currentIndex == 1 && unsure ? .unsure : .none) }
        }
    }
    func testC01TwentyUniqueServicesAndTagScoring() throws {
        let repo = try repository(); try repo.startCheckup()
        let catalog = repo.catalog
        var session = try XCTUnwrap(repo.checkup.session)
        for id in session.primaryQueue {
            let answer = CheckupAnswer(serviceID: id, choice: id == "qq_music" ? .paid : .none)
            session = try CheckupEngine.answering(session, answer: answer, catalog: catalog)
        }
        XCTAssertEqual(session.queue.count,20); XCTAssertEqual(Set(session.queue).count,20)
        XCTAssertEqual(catalog.first { $0.id == session.secondaryQueue!.first }?.tags?.contains("music"),true)
        XCTAssertEqual(CheckupEngine.secondary(session, catalog: catalog),session.secondaryQueue)
    }
    func testC02EightAnswersPersistAcrossRepositoryReload() throws {
        let container = try WalletRepository.container(inMemory: true), repo = try WalletRepository(container: container)
        try repo.startCheckup(); let id = repo.checkup.session!.id
        for _ in 0..<8 { try repo.answerCheckup(choice: .none) }
        let reopened = try WalletRepository(container: container)
        XCTAssertEqual(reopened.checkup.session?.id,id); XCTAssertEqual(reopened.checkup.session?.currentIndex,8)
        XCTAssertEqual(reopened.checkup.session?.currentServiceID,CheckupEngine.primaryIDs[8]); XCTAssertTrue(reopened.records.isEmpty)
    }
    func testC03FreezeSurvivesUndoAndDifferentFirstRoundAnswers() throws {
        let repo = try repository(); try repo.startCheckup()
        for _ in 0..<10 { try repo.answerCheckup(choice: .none) }
        let frozen = repo.checkup.session!.secondaryQueue
        for _ in 0..<10 { try repo.previousCheckupCard() }
        for _ in 0..<10 {
            let id = repo.checkup.session!.currentServiceID!
            try repo.answerCheckup(choice: .paid, member: seed(id, repo))
        }
        XCTAssertEqual(repo.checkup.session?.secondaryQueue,frozen)
    }
    func testC04BlankExistingFieldsRetainAmountDateAndID() throws {
        let repo = try repository(); var original = seed(CheckupEngine.primaryIDs[0],repo)
        original.amountMinor = 28800; original.cycle = .yearly; original.nextChargeOn = "2027-02-28"; original.recurrenceAnchorOn = "2027-02-28"; original.autoRenew = .on; original.notes = "保留备注"; original.planLabel = "保留套餐"
        try repo.save(original); original = repo.records[0]
        try repo.startCheckup()
        var blank = original; blank.amountMinor = nil; blank.nextChargeOn = nil; blank.recurrenceAnchorOn = nil; blank.planLabel = ""; blank.notes = ""
        try repo.answerCheckup(choice: .paid, member: blank)
        try finish(repo)
        let plan = try repo.checkupPlan(now: now), member = try XCTUnwrap(plan.records.first)
        XCTAssertEqual(member.amountMinor,original.amountMinor); XCTAssertEqual(member.nextChargeOn,original.nextChargeOn); XCTAssertEqual(member.id,original.id); XCTAssertEqual(member.notes,original.notes); XCTAssertEqual(member.planLabel,original.planLabel)
        XCTAssertEqual(plan.result.updated,1)
    }
    func testC05NoDefaultsToKeepArchiveRequiresSelection() throws {
        let repo = try repository(); let original = seed(CheckupEngine.primaryIDs[0],repo); try repo.save(original)
        try finish(repo, first: .none)
        XCTAssertFalse(try repo.checkupPlan(now: now).records[0].isArchived)
        try repo.selectCheckupArchive(serviceID:original.serviceID!,selected:true)
        XCTAssertTrue(try repo.checkupPlan(now: now).records[0].isArchived)
        try repo.selectCheckupArchive(serviceID:original.serviceID!,selected:false)
        XCTAssertFalse(try repo.checkupPlan(now: now).records[0].isArchived)
    }
    func testC06CommitIdempotentIncludingAfterReloadAndNewSession() throws {
        let container = try WalletRepository.container(inMemory: true), repo = try WalletRepository(container:container)
        try finish(repo); let id = repo.checkup.session!.id
        XCTAssertTrue(try repo.commitCheckup(sessionID:id,now:now)); XCTAssertFalse(try repo.commitCheckup(sessionID:id,now:now))
        XCTAssertEqual(repo.records.count,1); XCTAssertNil(repo.checkup.session)
        let reopened = try WalletRepository(container:container)
        try reopened.startCheckup(); let next = reopened.checkup.session!.id
        XCTAssertFalse(try reopened.commitCheckup(sessionID:id)); XCTAssertEqual(reopened.checkup.session?.id,next)
        XCTAssertEqual(reopened.records.count,1)
    }
    func testC06SingleSaveAndFailureRollsBackEntireCommit() throws {
        let container = try WalletRepository.container(inMemory:true)
        var fail = false, calls = 0
        let repo = try WalletRepository(container:container,commit:{ context in calls += 1; if fail { throw WalletError.storage("注入失败") }; try context.save() })
        try finish(repo, unsure:true); let before = repo.checkup, id = before.session!.id
        let count = calls; fail = true
        XCTAssertThrowsError(try repo.commitCheckup(sessionID:id,now:now)); XCTAssertEqual(calls,count+1)
        XCTAssertTrue(repo.records.isEmpty); XCTAssertEqual(repo.checkup,before)
        let disk = try WalletRepository(container:container); XCTAssertEqual(disk.checkup,before); XCTAssertTrue(disk.records.isEmpty)
        fail = false; XCTAssertTrue(try repo.commitCheckup(sessionID:id,now:now)); XCTAssertEqual(calls,count+2)
        XCTAssertEqual(repo.checkup.pending.count,1); XCTAssertEqual(repo.checkup.latest?.added,1)
    }
    func testAnswerSaveFailureDoesNotAdvanceDraft() throws {
        let container = try WalletRepository.container(inMemory:true); var fail = false
        let repo = try WalletRepository(container:container,commit:{ context in if fail { throw WalletError.storage("草稿失败") }; try context.save() })
        try repo.startCheckup(); let before = repo.checkup
        fail = true; XCTAssertThrowsError(try repo.answerCheckup(choice:.none)); XCTAssertEqual(repo.checkup,before)
    }
    func testC07UnsureDoesNotCreateWalletOrFees() throws {
        let repo = try repository(); try repo.startCheckup()
        for _ in 0..<20 { try repo.answerCheckup(choice:.unsure) }
        let id = repo.checkup.session!.id; try repo.commitCheckup(sessionID:id,now:now)
        XCTAssertTrue(repo.records.isEmpty); XCTAssertEqual(repo.checkup.pending.count,20); XCTAssertEqual(repo.checkup.latest?.currentCount,0)
        XCTAssertEqual(repo.checkup.latest?.summary.mainLabel,"尚未记录")
        try repo.resolvePending(serviceID:repo.checkup.pending[0].serviceID); XCTAssertEqual(repo.checkup.pending.count,19)
    }
    func testArchivedHaveRestoresOriginalInsteadOfDuplicate() throws {
        let repo = try repository(); var member = seed(CheckupEngine.primaryIDs[0],repo); member.isArchived = true; member.amountMinor = 3000; member.cycle = .monthly; try repo.save(member)
        try finish(repo); let plan = try repo.checkupPlan(now:now)
        XCTAssertEqual(plan.result.restored,1); XCTAssertEqual(plan.records.count,1); XCTAssertFalse(plan.records[0].isArchived); XCTAssertEqual(plan.records[0].id,member.id)
    }
    func testExistingEditAfterAnswerRequiresReReview() throws {
        let repo = try repository(); var member = seed(CheckupEngine.primaryIDs[0],repo); try repo.save(member)
        try finish(repo); member = repo.records[0]; member.notes = "之后修改"; try repo.save(member)
        XCTAssertThrowsError(try repo.checkupPlan(now:now)); XCTAssertNotNil(repo.checkup.session)
    }
    func testConcurrentNewServiceCannotBeOverwritten() throws {
        let repo = try repository(); try finish(repo)
        var member = seed(CheckupEngine.primaryIDs[0],repo); member.notes = "手动新增"; try repo.save(member)
        XCTAssertThrowsError(try repo.checkupPlan(now:now)); XCTAssertEqual(repo.records[0].notes,"手动新增")
    }
    func testPaidParentConversionDetachesChildWithoutRemovingBenefit() throws {
        let repo = try repository(); let parent = seed(CheckupEngine.primaryIDs[0],repo); try repo.save(parent)
        var child = Subscription(); child.name = "测试子权益"; child.category = .other; child.acquisition = .bundled; child.sourceSubscriptionID = parent.id; child.sourceName = parent.name; try repo.save(child)
        try finish(repo, first:.benefit)
        let plan = try repo.checkupPlan(now:now), value = try XCTUnwrap(plan.records.first { $0.id == child.id })
        XCTAssertNil(value.sourceSubscriptionID); XCTAssertEqual(value.sourceName,parent.name); XCTAssertEqual(value.acquisition,.bundled)
        XCTAssertTrue(plan.changes.contains { $0.id == child.id }); XCTAssertEqual(plan.result.summary.held,2)
    }
    func testIncompleteSubmitRejectedAndDiscardKeepsLatestAndWallet() throws {
        let repo = try repository(); try repo.startCheckup(); XCTAssertThrowsError(try repo.commitCheckup(sessionID:repo.checkup.session!.id))
        try repo.discardCheckup(); XCTAssertNil(repo.checkup.session)
        try finish(repo); try repo.commitCheckup(sessionID:repo.checkup.session!.id,now:now)
        let latest = repo.checkup.latest; try repo.startCheckup(); try repo.discardCheckup(); XCTAssertEqual(repo.checkup.latest,latest); XCTAssertEqual(repo.records.count,1)
    }
    func testLatestResultReplacesPreviousSnapshot() throws {
        let repo = try repository(); try finish(repo); try repo.commitCheckup(sessionID:repo.checkup.session!.id,now:now)
        let first = repo.checkup.latest!.sessionID
        try finish(repo,first:.none); let second = repo.checkup.session!.id; try repo.commitCheckup(sessionID:second,now:now)
        XCTAssertNotEqual(first,second); XCTAssertEqual(repo.checkup.latest?.sessionID,second); XCTAssertEqual(repo.checkup.committedSessionIDs.count,2)
    }
    func testPreferencesRemainSeparateFromCheckupStateRow() throws {
        let repo = try repository(); try repo.startCheckup(); let before = repo.checkup
        var p = repo.preferences; p.notificationShowsServiceName = false; p.exchangeRates["USD"] = "7"
        try repo.savePreferences(p); try repo.reload(); XCTAssertEqual(repo.checkup,before); XCTAssertEqual(repo.preferences,p)
    }
    func testBackupV2RoundtripDraftPendingLatestAndLedger() throws {
        let repo = try repository(); try finish(repo,unsure:true); try repo.commitCheckup(sessionID:repo.checkup.session!.id,now:now)
        try repo.startCheckup(); for _ in 0..<8 { try repo.answerCheckup(choice:.none) }
        let state = repo.checkup
        let backup = try BackupCodec.decode(BackupCodec.encode(records:repo.records,preferences:repo.preferences,checkup:state))
        XCTAssertEqual(backup.envelope.formatVersion,2); XCTAssertEqual(backup.envelope.checkup,state)
        let other = try repository(); try other.restore(backup); XCTAssertEqual(other.checkup,state); XCTAssertEqual(other.records,repo.records)
        try other.clearAll(); XCTAssertEqual(other.checkup,CheckupState()); XCTAssertTrue(other.records.isEmpty)
    }
    func testV1RestoreClearsCurrentCheckupAndRetainsWallet() throws {
        let repo = try repository(); try repo.startCheckup()
        var envelope = BackupEnvelope(exportedAt:Date(),appVersion:"0.1.2",subscriptions:[seed("apple_icloud",repo)],preferences:Preferences()); envelope.formatVersion = 1
        let backup = try BackupCodec.decode(JSONEncoder().encode(envelope)); try repo.restore(backup)
        XCTAssertEqual(repo.records.count,1); XCTAssertEqual(repo.checkup,CheckupState())
    }
    func testMalformedCheckupBackupRejected() throws {
        let repo = try repository(); try repo.startCheckup()
        func check(_ state:CheckupState) { XCTAssertThrowsError(try BackupCodec.encode(records:[],preferences:Preferences(),checkup:state)) }
        var state = repo.checkup; state.session!.currentIndex = 8; check(state)
        state = repo.checkup; state.session!.primaryQueue[1] = state.session!.primaryQueue[0]; check(state)
        state = repo.checkup; state.pending = [PendingService(serviceID:"x",name:"X"),PendingService(serviceID:"x",name:"Y")]; check(state)
        state = repo.checkup; state.committedSessionIDs = [state.session!.id]; check(state)
        state = repo.checkup; state.session!.archiveServiceIDs = ["apple_icloud"]; check(state)
    }
    func testTrialChangeDoesNotRestoreOldCurrentAmount() throws {
        let repo = try repository(); var original = seed(CheckupEngine.primaryIDs[0],repo)
        original.amountMinor = 3000; original.cycle = .monthly; try repo.save(original)
        try repo.startCheckup(); var trial = repo.records[0]; trial.isTrial = true; trial.amountMinor = nil; trial.nextPeriodAmountMinor = 4000
        try repo.answerCheckup(choice:.paid,member:trial); try finish(repo)
        let plan = try repo.checkupPlan(now:now)
        XCTAssertNil(plan.records[0].amountMinor); XCTAssertEqual(plan.result.summary.trials,1); XCTAssertEqual(plan.result.summary.eligible,0)
    }
    func testLifetimeChangeClearsOldDateAndReminder() throws {
        let repo = try repository(); var original = seed(CheckupEngine.primaryIDs[0],repo)
        original.amountMinor = 3000; original.cycle = .monthly; original.nextChargeOn = "2027-02-01"; original.reminderEnabled = true; try repo.save(original)
        try repo.startCheckup(); var lifetime = repo.records[0]; lifetime.cycle = .oneOff; lifetime.isLifetime = true; lifetime.nextChargeOn = nil; lifetime.recurrenceAnchorOn = nil; lifetime.reminderEnabled = false
        try repo.answerCheckup(choice:.paid,member:lifetime); try finish(repo)
        let value = try repo.checkupPlan(now:now).records[0]
        XCTAssertNil(value.nextChargeOn); XCTAssertNil(value.accessEndsOn); XCTAssertFalse(value.reminderEnabled)
    }
    func testMismatchedAnswerCannotAdvanceAndRenameKeepsFixedService() throws {
        let repo = try repository(); try repo.startCheckup(); let id = repo.checkup.session!.currentServiceID!
        var value = seed(id,repo)
        XCTAssertThrowsError(try repo.answerCheckup(choice:.benefit,member:value)); XCTAssertEqual(repo.checkup.session?.currentIndex,0)
        XCTAssertThrowsError(try repo.answerCheckup(choice:.none,member:value)); XCTAssertEqual(repo.checkup.session?.currentIndex,0)
        value.name = "我的云空间"; try repo.answerCheckup(choice:.paid,member:value)
        XCTAssertEqual(repo.checkup.session?.answers.first?.member?.name,"我的云空间")
        XCTAssertEqual(repo.checkup.session?.answers.first?.serviceID,id)
    }
    func testFrozenQueueWithoutPrimaryAnswersIsInvalidBackup() throws {
        let repo = try repository(); try repo.startCheckup(); var state = repo.checkup
        state.session!.secondaryQueue = CheckupEngine.secondary(state.session!,catalog:repo.catalog)
        XCTAssertThrowsError(try BackupCodec.encode(records:[],preferences:Preferences(),checkup:state))
    }
    func testBackupOfParentSourceChangeDraftRemainsValid() throws {
        let repo = try repository(); let parent = seed(CheckupEngine.primaryIDs[0],repo); try repo.save(parent)
        var child = Subscription(); child.name = "已有子权益"; child.category = .other; child.acquisition = .bundled; child.sourceSubscriptionID = parent.id; try repo.save(child)
        try repo.startCheckup(); var answer = repo.records.first { $0.id == parent.id }!; answer.acquisition = .bundled
        try repo.answerCheckup(choice:.benefit,member:answer)
        let data = try BackupCodec.encode(records:repo.records,preferences:repo.preferences,checkup:repo.checkup)
        let restored = try BackupCodec.decode(data); XCTAssertEqual(restored.envelope.checkup,repo.checkup)
        XCTAssertEqual(restored.envelope.subscriptions.first { $0.id == child.id }?.sourceSubscriptionID,parent.id)
    }
    func testStaleLinkedDraftCanBeBackedUpButCannotOverwriteChangedWallet() throws {
        let repo = try repository(); let parent = seed(CheckupEngine.primaryIDs[0],repo); try repo.save(parent)
        var child = seed(CheckupEngine.primaryIDs[1],repo); child.acquisition = .bundled; child.sourceSubscriptionID = parent.id; try repo.save(child)
        try repo.startCheckup(); try repo.answerCheckup(choice:.none)
        try repo.answerCheckup(choice:.benefit,member:repo.existing(serviceID:child.serviceID!)!)
        try repo.delete(parent)
        let data = try BackupCodec.encode(records:repo.records,preferences:repo.preferences,checkup:repo.checkup)
        XCTAssertEqual(try BackupCodec.decode(data).envelope.checkup,repo.checkup)
        try finish(repo,first:.none); XCTAssertThrowsError(try repo.checkupPlan(now:now))
    }
    func testCurrencyChangeCannotReuseBlankOriginalMinorUnits() throws {
        let repo = try repository(); var original = seed(CheckupEngine.primaryIDs[0],repo)
        original.amountMinor = 3000; original.cycle = .monthly; try repo.save(original)
        try repo.startCheckup(); var changed = repo.records[0]; changed.currency = .USD; changed.amountMinor = nil
        try repo.answerCheckup(choice:.paid,member:changed); try finish(repo)
        XCTAssertThrowsError(try repo.checkupPlan(now:now)); XCTAssertEqual(repo.records[0].currency,.CNY); XCTAssertEqual(repo.records[0].amountMinor,3000)
    }
    func testRemovingNextPriceDoesNotResurrectOriginalDuringCommit() throws {
        let repo = try repository(); var original = seed(CheckupEngine.primaryIDs[0],repo)
        original.amountMinor = 3000; original.nextPeriodAmountMinor = 4000; original.cycle = .monthly; try repo.save(original)
        try repo.startCheckup(); var resolved = repo.records[0]; resolved.nextPeriodAmountMinor = nil
        try repo.answerCheckup(choice:.paid,member:resolved); try finish(repo)
        let plan = try repo.checkupPlan(now:now)
        XCTAssertNil(plan.records[0].nextPeriodAmountMinor); XCTAssertEqual(plan.result.summary.monthly,30)
    }
    func testEndingTrialUsesEnteredCurrentPriceInsteadOfOldTrialFuturePrice() throws {
        let repo = try repository(); var original = seed(CheckupEngine.primaryIDs[0],repo)
        original.isTrial = true; original.nextPeriodAmountMinor = 3000; original.cycle = .monthly; try repo.save(original)
        try repo.startCheckup(); var resolved = repo.records[0]; resolved.isTrial = false; resolved.amountMinor = 2000; resolved.nextPeriodAmountMinor = nil
        try repo.answerCheckup(choice:.paid,member:resolved); try finish(repo)
        let plan = try repo.checkupPlan(now:now)
        XCTAssertNil(plan.records[0].nextPeriodAmountMinor); XCTAssertEqual(plan.result.summary.monthly,20)
    }
    func testBlankFutureFieldPreservesPriceUntilExplicitlyDisabled() throws {
        var original = Subscription(); original.name = "会员"; original.category = .other; original.cycle = .monthly; original.amountMinor = 3000; original.nextPeriodAmountMinor = 4000
        var input = original; input.nextPeriodAmountMinor = nil
        XCTAssertEqual(try CheckupEngine.preservingBlanks(input, original:original, preserveNextPeriodAmount:true).nextPeriodAmountMinor,4000)
        XCTAssertNil(try CheckupEngine.preservingBlanks(input, original:original, preserveNextPeriodAmount:false).nextPeriodAmountMinor)
        input.currency = .USD
        XCTAssertThrowsError(try CheckupEngine.preservingBlanks(input, original:original, preserveNextPeriodAmount:true))
        XCTAssertNil(try CheckupEngine.preservingBlanks(input, original:original, preserveNextPeriodAmount:false).nextPeriodAmountMinor)
    }
    func testRestoreFailureKeepsWalletAndAllCheckupState() throws {
        let container = try WalletRepository.container(inMemory:true); var fail = false
        let repo = try WalletRepository(container:container,commit:{ context in if fail { throw WalletError.storage("注入失败") }; try context.save() })
        try repo.startCheckup(); try repo.answerCheckup(choice:.unsure)
        let before = repo.checkup
        let backup = try BackupCodec.decode(BackupCodec.encode(records:[],preferences:Preferences()))
        fail = true; XCTAssertThrowsError(try repo.restore(backup)); XCTAssertEqual(repo.checkup,before)
        XCTAssertThrowsError(try repo.clearAll()); XCTAssertEqual(repo.checkup,before)
    }
}
