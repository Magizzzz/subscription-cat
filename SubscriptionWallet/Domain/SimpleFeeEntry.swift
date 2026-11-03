import Foundation

/// New entries have one RMB amount. Older backups retain their original fee
/// semantics until the user explicitly replaces that fee in the editor.
enum SimpleFeeEntry {
    static func isLegacy(_ value: Subscription) -> Bool {
        value.acquisition == .paid && (value.currency != .CNY || value.isTrial || value.nextPeriodAmountMinor != nil || value.amountConfidenceRaw == "estimated")
    }
    static func displayAmount(_ value: Subscription) -> String {
        guard value.currency == .CNY else { return "" }
        return Money.input(value.nextPeriodAmountMinor ?? value.amountMinor, .CNY)
    }
    static func needsConfirmation(_ draft: Subscription, text: String, original: Subscription?) throws -> Bool {
        guard draft.acquisition == .paid, let original, isLegacy(original), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let entered = try Money.parse(text, currency: .CNY)
        return original.currency != .CNY || entered != (original.nextPeriodAmountMinor ?? original.amountMinor) || draft.cycle != original.cycle
    }
    static func resolve(_ draft: Subscription, text: String, original: Subscription?, preserveBlank: Bool, allowLegacyReplacement: Bool = false) throws -> Subscription {
        guard draft.acquisition == .paid else { return draft }
        var result = draft
        let replacing = try needsConfirmation(draft, text: text, original: original)
        if let original, isLegacy(original), !replacing {
            result.cycle = original.cycle
            result.currency = original.currency
            result.amountMinor = original.amountMinor
            result.nextPeriodAmountMinor = original.nextPeriodAmountMinor
            result.isTrial = original.isTrial
            result.amountConfidenceRaw = original.amountConfidenceRaw
            return result
        }
        guard !replacing || allowLegacyReplacement else { throw WalletError.invalid("请先确认替换旧费用记录。") }
        result.currency = .CNY
        let entered = try Money.parse(text, currency: .CNY)
        result.amountMinor = entered ?? (preserveBlank && original?.acquisition == .paid && original?.currency == .CNY ? original?.amountMinor : nil)
        result.nextPeriodAmountMinor = nil
        result.isTrial = false
        result.amountConfidenceRaw = result.amountMinor == nil ? "unknown" : "actual"
        return result
    }
}
