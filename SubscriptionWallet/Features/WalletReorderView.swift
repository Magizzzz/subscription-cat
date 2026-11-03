import SwiftUI

/// 首页卡片的排序：整页是一张可拖动的列表，松手即保存，首页叠卡立刻按新顺序排。
struct WalletReorderView: View {
    @Environment(WalletRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Subscription] = []
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { member in
                        HStack(spacing: 12) {
                            BrandMark(member, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                                Text(Money.short(member)).font(.footnote).monospacedDigit().foregroundStyle(Theme.secondary).lineLimit(1)
                            }
                        }
                        .padding(.vertical, 2).listRowBackground(Theme.surface)
                        .accessibilityElement(children: .combine)
                    }.onMove(perform: move)
                } footer: {
                    Text("按住右侧的把手上下拖动，首页的卡片会按这个顺序叠放，最上面的排在最前。").font(.footnote)
                }
            }
            .environment(\.editMode, .constant(.active))
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("调整顺序").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() }.fontWeight(.semibold).accessibilityIdentifier("reorderDone") } }
            .alert("顺序没有保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(error ?? "") }
        }
        .onAppear { items = WalletOrdering.apply(repo.records.filter { !$0.isArchived }, order: repo.preferences.walletOrder) }
    }
    private func move(from: IndexSet, to: Int) {
        var next = items; next.move(fromOffsets: from, toOffset: to)
        do {
            // 已归档的记录接在后面，保留它们在“已归档”里的相对位置。
            try repo.saveWalletOrder(next.map(\.id) + WalletOrdering.apply(repo.records.filter(\.isArchived), order: repo.preferences.walletOrder).map(\.id))
            items = next
        } catch { self.error = error.localizedDescription }
    }
}
