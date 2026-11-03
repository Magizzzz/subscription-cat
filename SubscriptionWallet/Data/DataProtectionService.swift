import Foundation

@MainActor enum DataProtectionService {
    static func restore(_ backup: ValidatedBackup, repository: WalletRepository, notifications: NotificationCoordinator, now: Date = Date()) async throws {
        try repository.restore(backup)
        // No system interaction occurs before successful persistence.
        await notifications.reconcileAfterRestore(repository.records, preferences: repository.preferences, now: now)
    }
    static func clear(repository: WalletRepository, notifications: NotificationCoordinator) async throws {
        try repository.clearAll()
        await notifications.clearAll()
    }
}
