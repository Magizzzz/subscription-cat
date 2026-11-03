import SwiftUI

/// “找订阅” entry: one tap into quick recall (screenshot import was removed in 0.5.1).
struct FindHub: View {
    let pending: Int
    let startRecall: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("找订阅").font(.largeTitle.bold())
                Text("20 张卡，有就点「有」，没有就划走，约一分钟。").font(.subheadline).foregroundStyle(Theme.secondary)
            }
            FoundTray()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "hand.draw").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                        .frame(width: 34, height: 34).background(Theme.soft, in: Circle())
                    Text("快速回想").font(.headline)
                }
                Text("常用会员逐个问一遍，年付、联名、旧账号也能想起来。已经在钱包里的会显示现有金额，可以直接保持。")
                    .font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: "开始回想", action: startRecall).accessibilityIdentifier("startCheckup")
            }
            .padding(18).card(radius: 24)
            if pending > 0 { NavigationLink("待确认区 · \(pending) 项") { PendingServicesView() }.font(.subheadline).frame(maxWidth: .infinity).accessibilityIdentifier("pendingServices") }
            Label("全部在这台手机上完成，确认后才写入钱包", systemImage: "lock.shield").font(.caption).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 28)
    }
}
struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String
    @ScaledMetric(relativeTo: .subheadline) private var tile: CGFloat = 42
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.accent)
                .frame(width: tile, height: tile).background(Theme.soft, in: RoundedRectangle(cornerRadius: tile * 0.28, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(Theme.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}
struct CheckupView: View {
    @Environment(WalletRepository.self) private var repo
    @Environment(FindProgress.self) private var progress
    @AppStorage("dismissedCheckupResult") private var dismissedResult = ""
    var onWallet: () -> Void = {}
    @State private var error: String?
    @State private var discard = false
    var body: some View {
        Group {
            if let session = repo.checkup.session, session.status == .draft {
                if session.currentIndex < 20 { CheckupCardsView(session: session) }
                else { CheckupReviewView(session: session) }
            } else {
                ScrollView {
                    if let latest = repo.checkup.latest, latest.id.uuidString != dismissedResult {
                        VStack(spacing: 18) {
                            CheckupResultContent(result: latest, onWallet: onWallet)
                            Button("完成") { dismissedResult = latest.id.uuidString; withAnimation { progress.reset() } }
                                .font(.subheadline.weight(.medium)).frame(minHeight: 44).accessibilityIdentifier("finishFind")
                        }.padding(20)
                    } else {
                        FindHub(pending: repo.checkup.pending.count) { perform { try repo.startCheckup() } }
                    }
                }
            }
        }
        .background(Theme.background).navigationTitle(repo.checkup.session?.status == .draft ? "快速回想" : "").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if repo.checkup.session?.status == .draft {
                ToolbarItem(placement: .topBarTrailing) { Menu {
                    Button("暂存，返回钱包", action: onWallet)
                    Button("放弃本次草稿", role: .destructive) { discard = true }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("体检选项") }
            }
        }
        .alert("放弃本次体检草稿？", isPresented: $discard) {
            Button("保留草稿", role: .cancel) {}
            Button("放弃草稿", role: .destructive) { perform { try repo.discardCheckup() } }
        } message: { Text("本次未提交的回答将移除，钱包和上次结果不变。") }
        .alert("操作未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(error ?? "") }
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = error.localizedDescription } }
}
/// One-card-at-a-time deck: drag or tap 有/没有; "有" reveals common monthly tiers.
struct CheckupCardsView: View {
    @Environment(WalletRepository.self) private var repo
    let session: CheckupSession
    @State private var drag: CGSize = .zero
    @State private var choosing = false
    @State private var customOn = false
    @State private var custom = ""
    @State private var exitDirection: CGFloat = 1
    @State private var error: String?
    @State private var shake = 0
    @FocusState private var customFocused: Bool
    @State private var pawTick = 0
    @Environment(FindProgress.self) private var findProgress
    @Environment(\.dynamicTypeSize) private var typeSize
    private var item: CatalogItem? { repo.catalog.first { $0.id == session.currentServiceID } }
    private var nextItem: CatalogItem? {
        let i = session.currentIndex + 1
        return session.queue.indices.contains(i) ? repo.catalog.first { $0.id == session.queue[i] } : nil
    }
    private var existing: Subscription? { repo.records.first { $0.serviceID == session.currentServiceID } }
    private var spring: Animation { .spring(response: 0.42, dampingFraction: 0.8) }

    var body: some View {
        VStack(spacing: 0) {
            progress.padding(.top, 4).dynamicTypeSize(...DynamicTypeSize.accessibility1)
            Spacer(minLength: 10)
            if let item {
                // One stable scroll container: content is centred when it fits and scrolls when it
                // doesn't (small phones with tiers open, large text). Identity never changes, so the
                // custom-amount field keeps keyboard focus.
                GeometryReader { g in
                    ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        deck(item).frame(minHeight: g.size.height)
                    }.scrollBounceBehavior(.basedOnSize).scrollIndicators(.hidden)
                        .onChange(of: g.size.height) { _, _ in
                            // Runs after the keyboard has resized the area, so the field lands mid-view.
                            if customOn { withAnimation(spring) { proxy.scrollTo("customAmount", anchor: .center) } }
                        }
                    }
                        .mask { VStack(spacing: 0) { Color.black; LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 24) } }
                }
            } else {
                Text("服务目录已变化，请保留备份后重新开始本次体检。").foregroundStyle(Theme.warning)
            }
            Spacer(minLength: 10)
            // Bottom controls cap their text size, like system bars, so labels never truncate.
            controls.dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .padding(.horizontal, 20).padding(.bottom, 10)
        .background { ambient.ignoresSafeArea() }
        .sensoryFeedback(.impact(weight: .light), trigger: session.currentIndex)
        .alert("回答尚未保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(error ?? "") }
    }

    // MARK: pieces
    /// Back card first; ids stay stable so the back card is promoted, not re-created.
    private func deck(_ item: CatalogItem) -> some View {
        ZStack {
            ForEach([nextItem, item].compactMap { $0 }.filter { $0.id == item.id || !choosing }, id: \.id) { entry in
                card(entry, front: entry.id == item.id)
                    .zIndex(entry.id == item.id ? 1 : 0)
                    .transition(.asymmetric(insertion: .opacity,
                                            removal: .modifier(active: FlyAway(direction: exitDirection), identity: FlyAway(direction: 0))))
            }
        }.padding(.vertical, 8).frame(maxWidth: .infinity)
    }
    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.currentIndex < 10 ? "常见会员" : "顺着你的习惯").font(.footnote.weight(.medium)).foregroundStyle(Theme.secondary)
                Spacer()
                Text("\(min(session.currentIndex + 1, 20)) / 20").font(.footnote.weight(.semibold)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(session.currentIndex))).animation(spring, value: session.currentIndex)
                    .accessibilityLabel("已看 \(session.currentIndex)/20 · 第 \(session.currentIndex + 1) 张").accessibilityIdentifier("checkupProgress")
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.fill)
                    Capsule().fill(Theme.action).frame(width: max(6, g.size.width * Double(session.currentIndex) / 20))
                }
            }.frame(height: 4).animation(spring, value: session.currentIndex).accessibilityHidden(true)
        }
    }

    private var ambient: some View {
        let tint = Theme.fixed(item.map { BrandStyle.of($0.id, name: $0.name, category: Category(rawValue: $0.category)) }?.tint ?? 0xEAF7F0)
        return ZStack {
            Theme.background
            RadialGradient(colors: [tint.opacity(0.28), .clear], center: .top, startRadius: 20, endRadius: 420)
                .animation(.easeInOut(duration: 0.6), value: item?.id)
        }
    }

    @ViewBuilder private func card(_ item: CatalogItem, front: Bool) -> some View {
        let style = BrandStyle.of(item.id, name: item.name, category: Category(rawValue: item.category))
        VStack(spacing: 14) {
            BrandMark(style: style, assetID: item.id, size: choosing && front ? 64 : 96)
                .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
                .padding(.top, choosing && front ? 4 : 18)
            VStack(spacing: 4) {
                Text(item.name).font(choosing && front ? .title2.bold() : .title.bold()).multilineTextAlignment(.center).accessibilityIdentifier(front ? "checkupService" : "")
                Text(Category(rawValue: item.category)?.title ?? "").font(.subheadline).foregroundStyle(Theme.secondary)
            }
            if front, let existing {
                Text(existing.isArchived ? "钱包里有归档记录 · 回答“有”会恢复" : "钱包里已有 · \(Money.short(existing))")
                    .font(.caption.weight(.medium)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Theme.soft, in: Capsule())
            }
            if front && choosing { tierList(item).padding(.top, 4) }
            else if front { Text("你现在有这个会员吗？").font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 6).padding(.bottom, 18) }
            else { Color.clear.frame(height: 40) }
        }
        .padding(20).frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(front ? 0.10 : 0.04), radius: front ? 24 : 10, y: front ? 12 : 4)
        .overlay(alignment: .topLeading) { if front { stamp("有", color: Theme.accent, visible: drag.width > 30).rotationEffect(.degrees(-12)).padding(22) } }
        .overlay(alignment: .topTrailing) { if front { stamp("没有", color: Theme.secondary, visible: drag.width < -30).rotationEffect(.degrees(12)).padding(22) } }
        .scaleEffect(front ? 1 : 0.9).offset(y: front ? 0 : 34).opacity(front ? 1 : 0.55)
        .offset(x: front ? drag.width : 0, y: front ? drag.height * 0.15 : 0)
        .rotationEffect(.degrees(front ? Double(drag.width / 22) : 0), anchor: .bottom)
        .modifier(Shake(amount: front ? CGFloat(shake) : 0))
        .allowsHitTesting(front)
        .gesture(front && !choosing && !typeSize.isAccessibilitySize ? swipe : nil)
        .accessibilityElement(children: .contain).accessibilityIdentifier(front ? "checkupCard" : "checkupNextCard")
        .accessibilityHidden(!front)
    }

    private func stamp(_ text: String, color: Color, visible: Bool) -> some View {
        Label(text, systemImage: "pawprint.fill").font(.headline.weight(.heavy)).foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .overlay(Capsule().stroke(color, lineWidth: 2))
            .opacity(visible ? 1 : 0).scaleEffect(visible ? 1 : 0.8).animation(.snappy(duration: 0.18), value: visible)
            .accessibilityHidden(true)
    }

    @ViewBuilder private func tierList(_ item: CatalogItem) -> some View {
        let tiers = item.tiers ?? []
        VStack(spacing: 8) {
            if let existing, !existing.isArchived, existing.acquisition != .unknown {
                TierButton(title: "保持现有", detail: existing.acquisition == .paid ? Money.short(existing) : existing.acquisition.title, highlighted: true) { keep(existing) }
                    .accessibilityIdentifier("checkupKeep").staggered(0, on: choosing)
            }
            ForEach(Array(tiers.enumerated()), id: \.offset) { i, tier in
                if let minor = tier.minor {
                    TierButton(title: "\(Money.display(Money.decimal(minor, .CNY))) / 月", detail: tier.label) { pick(minor) }
                        .accessibilityIdentifier("checkupTier-\(i)").staggered(i + 1, on: choosing)
                }
            }
            if customOn {
                HStack(spacing: 8) {
                    Text("¥").font(.title3.weight(.semibold)).foregroundStyle(Theme.secondary)
                    TextField("每月金额", text: $custom).keyboardType(.decimalPad).font(.title3.weight(.semibold)).monospacedDigit()
                        .focused($customFocused).accessibilityIdentifier("checkupCustomAmount")
                    Text("/ 月").foregroundStyle(Theme.secondary)
                    Button { submitCustom() } label: {
                        Image(systemName: "arrow.right").font(.headline).foregroundStyle(.white).frame(width: 40, height: 40).background(Theme.action, in: Circle())
                    }.accessibilityLabel("确定").accessibilityIdentifier("checkupCustomDone")
                }.padding(.leading, 16).padding(.trailing, 6).frame(minHeight: 52).id("customAmount")
                    .background(Theme.fill, in: Capsule()).transition(.scale(scale: 0.96).combined(with: .opacity))
            } else {
                TierButton(title: "其他金额", detail: "自己填") { withAnimation(spring) { customOn = true }; customFocused = true }
                    .accessibilityIdentifier("checkupTierCustom").staggered(tiers.count + 1, on: choosing)
            }
            Text("参考价，以实际支付为准 · 年付可在详情里改").font(.caption2).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).padding(.top, 2)
        }
    }

    private var controls: some View {
        HStack(alignment: .center) {
            Button { perform { try repo.previousCheckupCard() } } label: {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.secondary)
                    .frame(width: 48, height: 48).background(Theme.surface, in: Circle()).shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            }.buttonStyle(PressScale()).disabled(session.currentIndex == 0).opacity(session.currentIndex == 0 ? 0.4 : 1)
                .accessibilityLabel("撤回上一张").accessibilityIdentifier("checkupBack")
            Spacer()
            if choosing {
                Button { withAnimation(spring) { choosing = false; customOn = false; custom = ""; customFocused = false } } label: {
                    Label("重新选择", systemImage: "chevron.left").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 22).frame(height: 56).background(Theme.surface, in: Capsule()).shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                }.buttonStyle(PressScale()).transition(.scale.combined(with: .opacity)).accessibilityIdentifier("checkupCollapse")
            } else {
                HStack(spacing: 22) {
                    AnswerButton(title: "没有", symbol: "xmark", filled: false) { answerNone() }.accessibilityIdentifier("checkup-none")
                    AnswerButton(title: "有", symbol: "checkmark", filled: true) { reveal() }.accessibilityIdentifier("checkup-paid")
                        .pawBurst(trigger: pawTick)
                }.transition(.scale.combined(with: .opacity))
            }
            Spacer()
            Color.clear.frame(width: 48, height: 48)
        }.animation(spring, value: choosing)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { drag = $0.translation }
            .onEnded { value in
                let x = value.translation.width + value.predictedEndTranslation.width * 0.25
                if x < -120 { answerNone() }
                else if x > 120 { withAnimation(spring) { drag = .zero }; reveal() }
                else { withAnimation(spring) { drag = .zero } }
            }
    }

    // MARK: actions
    private func reveal() { withAnimation(spring) { choosing = true } }
    private var base: Subscription {
        guard let item else { return Subscription() }
        let previous = session.answers.first { $0.serviceID == item.id }
        let unchanged = previous?.baseID == existing?.id && previous?.baseUpdatedAt == existing?.updatedAt
        var value = (unchanged ? previous?.member : nil) ?? existing ?? Subscription()
        if value.serviceID == nil { value.serviceID = item.id; value.name = item.name; value.categoryRaw = item.category; value.reminderLeadDays = repo.preferences.defaultLeadDays }
        return value
    }
    private func pick(_ minor: Int64) {
        var v = base
        v.acquisition = .paid; v.sourceSubscriptionID = nil; v.sourceName = ""
        v.currency = .CNY; v.amountMinor = minor; v.cycle = .monthly
        v.isTrial = false; v.isLifetime = false; v.nextPeriodAmountMinor = nil; v.amountConfidenceRaw = "actual"
        pawTick += 1
        let found = FindProgress.Item(serviceID: v.serviceID ?? "", source: .checkup, monthlyMinor: minor)
        fly(1) { try repo.answerCheckup(choice: .paid, member: v); withAnimation { findProgress.add([found]) } }
    }
    private func keep(_ e: Subscription) {
        let found = FindProgress.Item(serviceID: e.serviceID ?? "", source: .checkup, monthlyMinor: e.amountMinor)
        fly(1) { try repo.answerCheckup(choice: e.acquisition == .paid ? .paid : .benefit, member: e); withAnimation { findProgress.add([found]) } }
    }
    private func submitCustom() {
        do {
            guard let minor = try Money.parse(custom, currency: .CNY) else { throw WalletError.invalid("请输入每月金额。") }
            customFocused = false; pick(minor)
        } catch { withAnimation(.default) { shake += 1 }; self.error = error.localizedDescription }
    }
    private func answerNone() { fly(-1) { try repo.answerCheckup(choice: .none) } }
    private func fly(_ direction: CGFloat, _ action: @escaping () throws -> Void) {
        exitDirection = direction
        DispatchQueue.main.async {
            withAnimation(spring) {
                do { try action(); drag = .zero; choosing = false; customOn = false; custom = "" }
                catch { drag = .zero; self.error = error.localizedDescription }
            }
        }
    }
    private func perform(_ action: () throws -> Void) { do { try withAnimation(spring) { try action() }; choosing = false } catch { self.error = error.localizedDescription } }
}

private struct FlyAway: ViewModifier {
    let direction: CGFloat
    func body(content: Content) -> some View {
        content.offset(x: direction * 520, y: abs(direction) * 40).rotationEffect(.degrees(Double(direction) * 16)).opacity(direction == 0 ? 1 : 0)
    }
}
private struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat { get { amount } set { amount = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform { ProjectionTransform(CGAffineTransform(translationX: 8 * sin(amount * .pi * 4), y: 0)) }
}
private extension View {
    /// Tiers rise in one after another when the card opens.
    func staggered(_ index: Int, on: Bool) -> some View {
        transition(.asymmetric(insertion: .offset(y: 18).combined(with: .opacity).animation(.spring(response: 0.42, dampingFraction: 0.78).delay(Double(index) * 0.045)), removal: .opacity))
    }
}
struct TierButton: View {
    let title: String
    let detail: String
    var highlighted = false
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var size
    var body: some View {
        Button(action: action) {
            AdaptiveRow {
                Text(title).font(.headline).monospacedDigit().foregroundStyle(highlighted ? Theme.accent : Theme.text)
                if !size.isAccessibilitySize { Spacer() }
                Text(detail).font(.footnote).foregroundStyle(Theme.secondary).lineLimit(size.isAccessibilitySize ? nil : 1)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.vertical, size.isAccessibilitySize ? 12 : 0).frame(minHeight: 52)
                .background(highlighted ? Theme.soft : Theme.fill, in: RoundedRectangle(cornerRadius: 26, style: .continuous)).contentShape(RoundedRectangle(cornerRadius: 26))
        }.buttonStyle(PressScale()).accessibilityElement(children: .combine)
    }
}
struct AnswerButton: View {
    let title: String
    let symbol: String
    let filled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 24, weight: .bold))
                    .foregroundStyle(filled ? .white : Theme.text)
                    .frame(width: 72, height: 72)
                    .background(filled ? AnyShapeStyle(Theme.actionGradient) : AnyShapeStyle(Theme.surface), in: Circle())
                    .shadow(color: filled ? Theme.action.opacity(0.35) : .black.opacity(0.08), radius: 12, y: 5)
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
            }
        }.buttonStyle(PressScale()).accessibilityElement(children: .ignore).accessibilityLabel(title).accessibilityAddTraits(.isButton)
    }
}
