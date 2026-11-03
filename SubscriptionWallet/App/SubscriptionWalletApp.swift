import SwiftUI
import SwiftData

@main struct SubscriptionWalletApp: App {
    private let repository: WalletRepository?
    private let startupError: String?
    @State private var notifications = NotificationCoordinator()
    // UI tests get a throwaway store so one test's finds never leak into the next.
    @State private var findProgress = ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-ui-testing") })
        ? FindProgress(defaults: UserDefaults(suiteName: "find-ui-\(UUID())")!) : FindProgress()
    init() {
        do {
            var inMemory = false
            var storeURL: URL?
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            inMemory = args.contains("-ui-testing")
            if args.contains("-ui-testing-disk") {
                let directory = URL.applicationSupportDirectory.appendingPathComponent("UITestStore", isDirectory: true)
                if args.contains("-ui-reset-store") && FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                storeURL = directory.appendingPathComponent("wallet.store")
            }
            #endif
            let repo = try WalletRepository(container: WalletRepository.container(inMemory: inMemory, storeURL: storeURL))
            // 只在正式包：把用户自己的会员补进钱包（已有的不动、删掉的不加回）。失败则下次再试。
            if Bundle.main.bundleIdentifier == MyMemberships.seedBundleID { MyMemberships.seedPending(into: repo) }
            if Bundle.main.bundleIdentifier == MyMemberships.seedBundleID, !UserDefaults.standard.bool(forKey: MyMemberships.upgradeKey),
               (try? repo.upgradeSeeds()) != nil { UserDefaults.standard.set(true, forKey: MyMemberships.upgradeKey) }
            #if DEBUG
            try PreviewFixtures.populate(repo)
            #endif
            repository = repo; startupError = nil
        } catch { repository = nil; startupError = error.localizedDescription }
    }
    var body: some Scene {
        WindowGroup {
            if let repository { RootView().environment(repository).environment(notifications).environment(findProgress).tint(Theme.accent) }
            else {
                ContentUnavailableView { Label("暂时无法打开钱包", systemImage: "externaldrive.badge.exclamationmark") } description: {
                    Text("原有数据未被清空。请保留本机数据并重启 App，或联系开发者排查。\n\(startupError ?? "")")
                }
            }
        }
    }
}
private struct ShowWalletKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
extension EnvironmentValues {
    /// Switches to the wallet tab (e.g. after clearing all local data).
    var showWallet: () -> Void { get { self[ShowWalletKey.self] } set { self[ShowWalletKey.self] = newValue } }
}
struct RootView: View {
    @Environment(WalletRepository.self) var repo
    @Environment(NotificationCoordinator.self) var notifications
    @Environment(\.scenePhase) var phase
    @State var tab = 0
    @State var routed: Subscription?
    @State private var reminderRoute = false
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var welcome = false
    @State private var profileStack = UUID()
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { WalletView(onCheckup: { tab = 1 }) }.tabItem { Label("钱包", systemImage: "wallet.pass") }.tag(0)
            NavigationStack { CheckupView(onWallet: { tab = 0 }) }.tabItem { Label("体检", systemImage: "checklist") }.tag(1)
            NavigationStack { StatisticsView() }.tabItem { Label("统计", systemImage: "chart.bar") }.tag(2)
            NavigationStack { ProfileView() }.id(profileStack).tabItem { Label("我的", systemImage: "person") }.tag(3)
        }
        .environment(\.showWallet, { tab = 0; profileStack = UUID() })
        .badgeToast()
        .background(Theme.background)
        .task { await reconcile() }
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            let testing = args.contains("-ui-testing") || args.contains("-ui-testing-disk")
            welcome = args.contains("-show-welcome") || (!hasSeenWelcome && !testing)
        }
        .fullScreenCover(isPresented: $welcome) { WelcomeView { hasSeenWelcome = true; welcome = false } }
        .onChange(of: phase) { _, value in if value == .active { Task { await reconcile() } } }
        .onChange(of: notifications.routeID) { _, id in
            guard let id else { return }
            if let s = repo.records.first(where: { $0.id == id }) { routed = s }
            else { tab = 0; notifications.removedRecordNotice = true }
            notifications.routeID = nil
        }
        .onChange(of: notifications.showReminderCenter) { _, show in if show { tab = 0; reminderRoute = true; notifications.showReminderCenter = false } }
        .sheet(isPresented: $reminderRoute) { NavigationStack { ReminderCenterView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { reminderRoute = false } } } } }
        .sheet(item: $routed) { s in NavigationStack { SubscriptionDetailView(id: s.id).toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { routed = nil } } } } }
        .alert("这项记录已移除", isPresented: Binding(get: { notifications.removedRecordNotice }, set: { notifications.removedRecordNotice = $0 })) { Button("知道了", role: .cancel) {} }
    }
    var checkupTabTitle: String { if let s = repo.checkup.session, s.status == .draft { return "继续体检 · 已看 \(s.currentIndex)/20" }; return "体检" }
    func reconcile() async { await notifications.reconcile(repo.records, preferences: repo.preferences) }
}
