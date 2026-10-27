import SwiftUI

@main
struct RatedApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.fontScale, store.fontScale)
                .preferredColorScheme(store.themeMode.colorScheme)
                .tint(W.accent)
        }
    }
}

enum Route: Hashable {
    case movie(Movie)
    case user(String)
    case notifications
    case settings(SettingsSection?)
}

enum Tab: String, Hashable { case home, upcoming, search, leaderboard, profile }

extension View {
    /// Registers every push destination so any tab's NavigationStack can route anywhere.
    func ratedDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .movie(let m): MovieDetailView(movie: m)
            case .user(let h): UserProfileView(handle: h)
            case .notifications: NotificationsView()
            case .settings(let s): SettingsView(initial: s)
            }
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        ZStack(alignment: .bottom) {
            W.bg.ignoresSafeArea()
            Group {
                switch store.authState {
                case .loggedOut: LoginView()
                case .choosingUsername: UsernameView()
                case .loggedIn:
                    if store.onboardingActive { OnboardingRankView() } else { MainTabView() }
                }
            }
            .transition(.opacity)
            if let t = store.toast {
                ToastView(toast: t)
                    .padding(.bottom, 70)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { store.toast = nil }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !store.online {
                Text("⚠ OFFLINE · Changes won't sync until you reconnect")
                    .mono(9, .bold).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
                    .background(W.dim)
            }
        }
        .animation(.snappy, value: store.toast)
        .animation(.easeInOut, value: store.authState)
        .animation(.easeInOut, value: store.onboardingActive)
        .fullScreenCover(item: $store.rankTarget) { movie in
            RankView(movie: movie).environment(store).environment(\.fontScale, store.fontScale)
        }
    }
}

struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @State private var tab: Tab = .home
    @State private var paths: [Tab: NavigationPath] = [:]

    private func path(_ t: Tab) -> Binding<NavigationPath> {
        Binding(get: { paths[t] ?? NavigationPath() }, set: { paths[t] = $0 })
    }

    var body: some View {
        TabView(selection: Binding(get: { tab }, set: { new in
            // Re-tapping the active tab pops to root, like the web nav's onNav.
            if new == tab { paths[new] = NavigationPath() }
            Haptics.light()
            tab = new
        })) {
            stack(.home) { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(Tab.home)
            stack(.upcoming) { UpcomingView() }
                .tabItem { Label("Upcoming", systemImage: "calendar") }.tag(Tab.upcoming)
            stack(.search) { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(Tab.search)
            stack(.leaderboard) { LeaderboardView() }
                .tabItem { Label("Board", systemImage: "trophy.fill") }.tag(Tab.leaderboard)
            stack(.profile) { ProfileView() }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(Tab.profile)
        }
        .onChange(of: store.rankHistory.count) { old, new in
            // After a ranking lands, show the updated list (App.jsx → "profile").
            if new > old { tab = .profile; paths[.profile] = NavigationPath() }
        }
    }

    private func stack<V: View>(_ t: Tab, @ViewBuilder _ root: () -> V) -> some View {
        NavigationStack(path: path(t)) {
            root()
                .ratedDestinations()
                .toolbarBackground(W.bg, for: .navigationBar)
        }
    }
}
