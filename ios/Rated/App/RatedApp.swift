import SwiftUI

@main
struct RatedApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(W.accent)
        }
    }
}

enum Route: Hashable {
    case movie(Movie)
    case settings(SettingsSection?)
}

enum Tab: String, Hashable { case home, search, leaderboard, profile }

extension View {
    /// Registers every push destination so any tab's NavigationStack can route anywhere.
    func ratedDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .movie(let m): MovieDetailView(movie: m)
            case .settings(let s): SettingsView(initial: s)
            }
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                Text("Offline. Changes sync on reconnect.")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
                    .background(Color(white: 0.3))
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: store.toast)
        .animation(.easeInOut, value: store.authState)
        .animation(.easeInOut, value: store.onboardingActive)
        .fullScreenCover(item: $store.rankTarget) { movie in
            RankView(movie: movie).environment(store)
        }
    }
}

struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @State private var tab: Tab = .home
    @State private var paths: [Tab: NavigationPath] = [:]

    init() {
        let font = UIFont.systemFont(ofSize: 14)
        let look = UITabBarAppearance()
        look.configureWithDefaultBackground()
        for item in [look.stackedLayoutAppearance, look.inlineLayoutAppearance, look.compactInlineLayoutAppearance] {
            item.normal.titleTextAttributes[.font] = font
            item.selected.titleTextAttributes[.font] = font
            item.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: -8)
            item.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: -8)
        }
        UITabBar.appearance().standardAppearance = look
        UITabBar.appearance().scrollEdgeAppearance = look
    }

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
                .tabItem { Text("Home") }.tag(Tab.home)
            stack(.search) { SearchView() }
                .tabItem { Text("Search") }.tag(Tab.search)
            stack(.leaderboard) { LeaderboardView() }
                .tabItem { Text("Board") }.tag(Tab.leaderboard)
            stack(.profile) { ProfileView() }
                .tabItem { Text("Profile") }.tag(Tab.profile)
        }
        .onChange(of: store.rankCount) { old, new in
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
