import Foundation

enum CheckupBackupValidator {
    static func validate(_ state: CheckupState, records: [Subscription], preferences: Preferences) throws {
        func require(_ condition: Bool) throws { if !condition { throw WalletError.invalid("体检备份数据不完整或不合法，原数据未修改。") } }
        func validID(_ id: String) -> Bool { !id.isEmpty && id.count <= 100 && id.trimmingCharacters(in: .whitespacesAndNewlines) == id }
        try require(state.pending.count <= 2000 && Set(state.pending.map(\.serviceID)).count == state.pending.count)
        try require(state.committedSessionIDs.count <= 10000 && Set(state.committedSessionIDs).count == state.committedSessionIDs.count)
        for p in state.pending { try require(validID(p.serviceID) && !p.name.isEmpty && p.name.count <= 40 && BackupCodec.validTimestamp(p.updatedAt)) }
        if let result = state.latest {
            try require(state.committedSessionIDs.contains(result.sessionID) && BackupCodec.validTimestamp(result.completedAt))
            let s = result.summary
            for n in [result.added, result.updated, result.restored, result.archived, result.currentCount, s.held, s.paid, s.gifted, s.unknownSource, s.trials, s.missing, s.missingRate, s.review, s.oneOffCount, s.eligible, s.knownTrialCount, s.knownOneOffCount] { try require((0...2000).contains(n)) }
            try require(result.currentCount == s.held && s.held == s.paid + s.gifted + s.unknownSource)
            try require(s.annual >= 0 && s.trialAnnual >= 0 && s.oneOff >= 0)
        }
        guard let s = state.session else { return }
        try require(s.primaryQueue.count == 10 && (s.secondaryQueue == nil || s.secondaryQueue?.count == 10))
        try require(Set(s.queue).count == s.queue.count && s.queue.allSatisfy(validID))
        try require((0...20).contains(s.currentIndex) && (s.currentIndex < 10 || s.secondaryQueue != nil))
        try require(s.answers.count <= 20 && Set(s.answers.map(\.serviceID)).count == s.answers.count)
        try require(Set(s.answers.map(\.serviceID)).isSubset(of: Set(s.queue)))
        try require(s.archiveServiceIDs.count <= 20 && Set(s.archiveServiceIDs).count == s.archiveServiceIDs.count)
        try require(s.archiveServiceIDs.allSatisfy { id in s.answers.contains { $0.serviceID == id && $0.choice == .none } })
        try require(BackupCodec.validTimestamp(s.createdAt) && BackupCodec.validTimestamp(s.updatedAt))
        try require(s.queue.prefix(s.currentIndex).allSatisfy { id in s.answers.contains { $0.serviceID == id } })
        if s.secondaryQueue != nil { try require(s.primaryQueue.allSatisfy { id in s.answers.contains { $0.serviceID == id } }) }
        if s.status == .completed { try require(s.currentIndex == 20 && state.committedSessionIDs.contains(s.id)) }
        else { try require(!state.committedSessionIDs.contains(s.id)) }
        let drafts = s.answers.compactMap(\.member)
        try require(Set(drafts.map(\.id)).count == drafts.count)
        for a in s.answers {
            try require((a.baseID == nil) == (a.baseUpdatedAt == nil))
            if let date = a.baseUpdatedAt { try require(BackupCodec.validTimestamp(date)) }
            if a.choice.hasMembership {
                guard let value = a.member else { try require(false); return }
                try require(!records.contains { $0.id == value.id && $0.serviceID != value.serviceID })
                if let base = a.baseID { try require(value.id == base) }
                try require(value.serviceID == a.serviceID && (a.choice == .paid ? value.acquisition == .paid : [.bundled, .gifted].contains(value.acquisition)))
                // Drafts are historical snapshots: a parent may have been deleted or
                // changed since answering. Validate fields here; recheck live relationships
                // and baseline timestamps in the atomic submission plan.
                if let parent = value.sourceSubscriptionID { try require(value.acquisition == .bundled && parent != value.id) }
                var fields = value; fields.sourceSubscriptionID = nil
                _ = try BackupCodec.validate(BackupEnvelope(exportedAt: Date(), appVersion: "draft-validation", subscriptions: [fields], preferences: preferences))
            } else { try require(a.member == nil) }
        }
    }
}
