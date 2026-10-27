import SwiftUI

struct UpcomingView: View {
    @Environment(AppStore.self) private var store
    @State private var genre = "All"
    @State private var movies: [Movie] = Mock.upcoming

    var body: some View {
        let filtered = movies
            .filter { genre == "All" || $0.genres.contains(genre) }
            .sorted { ($0.daysUntilRelease ?? 0) < ($1.daysUntilRelease ?? 0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("◈ UPCOMING · MUST SEE").mono(14, .heavy).foregroundStyle(W.text).padding(.top, 6)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(Mock.allGenres, id: \.self) { g in Chip(label: g, selected: genre == g) { genre = g } } }
                }
                if filtered.isEmpty { EmptyStateView(icon: "📅", title: "No upcoming \(genre) films", subtitle: "Try another genre") }
                ForEach(filtered) { u in row(u) }
            }
            .padding(.horizontal, 18).padding(.bottom, 24)
        }
        .background(W.bg)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { Catalog.shared.invalidate(); movies = await Catalog.shared.upcoming() }
        .task { movies = await Catalog.shared.upcoming() }
    }

    private func row(_ u: Movie) -> some View {
        let inWL = store.watchlist.contains(u.id)
        return VStack(spacing: 10) {
            NavigationLink(value: Route.movie(u)) {
                HStack(alignment: .top, spacing: 12) {
                    PosterView(url: u.posterURL, title: u.title, width: 56, height: 78, radius: 8)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(u.title).mono(13, .heavy).foregroundStyle(W.text)
                        Text(([u.directors.first ?? u.genres.first].compactMap { $0 } + [u.genres.joined(separator: ", ")]).joined(separator: " · "))
                            .mono(9).foregroundStyle(W.dim).lineLimit(1)
                        if let r = u.mustSeeReason { Text(r).mono(10).foregroundStyle(W.gold) }
                        HStack(spacing: 10) {
                            T("📅 \(TimeFmt.releaseDate(u.releaseDate))").mono(10).foregroundStyle(W.dim)
                            Text(TimeFmt.countdown(u.releaseDate)).mono(10, .bold).foregroundStyle(W.accent)
                        }
                        if u.watchlistCount > 0 || u.anticipationScore != nil {
                            Text([u.watchlistCount > 0 ? "👀 \(u.watchlistCount.formatted()) watching" : nil, u.anticipationScore.map { "📊 \($0) hype" }].compactMap { $0 }.joined(separator: " · "))
                                .mono(9).foregroundStyle(W.dim)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            RatedButton(title: inWL ? "◆ IN WATCHLIST" : "+ WATCHLIST", style: inWL ? .tinted(W.blue) : .accent, small: true) { store.toggleWatchlist(u.id) }
                .accessibilityIdentifier("watchlist-\(u.id)")
        }
        .card(radius: 14, padding: 14)
    }
}

struct LeaderboardView: View {
    @Environment(AppStore.self) private var store
    @State private var tab = "global"
    @State private var topRated: [Movie]?

    private struct Row: Identifiable { var handle: String; var avatar: String; var label: String; var rated: Int; var streak: Int; var badge: String; var isYou: Bool; var id: String { handle } }

    private var global: [Row] {
        var rows = Mock.profileOrder.filter { $0 != store.handle }.compactMap { h -> Row? in
            guard let p = Mock.profiles[h], !store.blockedUsers.contains(h) else { return nil }
            return Row(handle: h, avatar: p.avatar, label: h, rated: p.moviesRated, streak: p.streak, badge: p.badge, isYou: false)
        }
        let n = store.rankedIds.count
        rows.append(Row(handle: store.handle, avatar: store.avatarInitial, label: store.displayName.isEmpty ? store.handle : store.displayName,
                        rated: n, streak: store.streak.count, badge: n >= 50 ? "🔥" : "", isYou: true))
        return rows.sorted { $0.rated > $1.rated }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("◆ LEADERBOARD").mono(14, .heavy).foregroundStyle(W.text).padding(.top, 6)
                UnderlineTabs(tabs: [("global", "Most Rated"), ("friends", "Friends' Picks"), ("toprated", "Top Rated")], selection: $tab)
                    .padding(.bottom, 4)
                switch tab {
                case "global":
                    ForEach(Array(global.enumerated()), id: \.element.id) { i, u in userRow(u, i) }
                case "friends":
                    ForEach(Mock.friendsPicks, id: \.rank) { p in
                        if let m = Catalog.shared.find(p.movieId) {
                            NavigationLink(value: Route.movie(m)) {
                                movieRow(m, index: p.rank - 1, sub: "Rated by \(p.ratedBy.prefix(2).joined(separator: ", "))\(p.count > 2 ? " +\(p.count - 2) more" : "")",
                                         value: "★ \(p.avg)", unit: "AVG")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                default:
                    if let list = topRated {
                        if list.isEmpty { EmptyStateView(icon: "📡", title: "Top Rated unavailable", subtitle: "The TMDB proxy isn't configured on this backend.") }
                        ForEach(Array(list.prefix(20).enumerated()), id: \.element.id) { i, m in
                            NavigationLink(value: Route.movie(m)) {
                                movieRow(m, index: i, sub: "\(m.releaseYear.map(String.init) ?? "")\(m.userRatingCount > 0 ? " · \(m.userRatingCount.formatted()) votes" : "")",
                                         value: "★ \(m.avgUserRating.map { String(format: "%.1f", $0) } ?? "—")", unit: "TMDB")
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        ProgressView("Loading top rated films...").mono(11).frame(maxWidth: .infinity).padding(30)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 24)
        }
        .background(W.bg)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { Catalog.shared.invalidate(); topRated = await Catalog.shared.topRated() ?? [] }
        .task(id: tab) { if tab == "toprated", topRated == nil { topRated = await Catalog.shared.topRated() ?? [] } }
    }

    @ViewBuilder
    private func userRow(_ u: Row, _ i: Int) -> some View {
        let content = HStack(spacing: 10) {
            T(Medal.label(i)).mono(i < 3 ? 15 : 11, .black).foregroundStyle(W.dim).frame(width: 24)
            AvatarView(initial: u.avatar, size: 30, image: u.isYou ? store.profilePic : nil)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(u.label).mono(11, .bold).foregroundStyle(u.isYou ? W.accent : W.text)
                    if u.isYou { Text("(you)").mono(8).foregroundStyle(W.dim) }
                    T(u.badge)
                }
                if u.streak > 0 { T("🔥 \(u.streak)w streak").mono(9).foregroundStyle(W.dim) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(u.rated.formatted()).mono(15, .black).foregroundStyle(W.gold)
                Text("FILMS").mono(7).foregroundStyle(W.dim)
            }
        }
        .card(radius: 10, fill: u.isYou ? W.accentDim : i < 3 ? W.gold.opacity(0.04) : W.card,
              stroke: u.isYou ? W.accent.opacity(0.25) : i < 3 ? W.gold.opacity(0.2) : W.border, padding: 9)
        if u.isYou { content } else { NavigationLink(value: Route.user(u.handle)) { content }.buttonStyle(.plain) }
    }

    private func movieRow(_ m: Movie, index i: Int, sub: String, value: String, unit: String) -> some View {
        HStack(spacing: 10) {
            T(Medal.label(i)).mono(i < 3 ? 15 : 11, .black).foregroundStyle(W.dim).frame(width: 24)
            PosterView(url: m.posterURL, title: m.title, width: 32, height: 44, radius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.title).mono(11, .bold).foregroundStyle(W.text).lineLimit(1)
                Text(sub).mono(9).foregroundStyle(W.dim).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(value).mono(14, .black).foregroundStyle(W.gold)
                Text(unit).mono(7).foregroundStyle(W.dim)
            }
        }
        .card(radius: 10, fill: i < 3 ? W.accent.opacity(0.04) : W.card, stroke: i < 3 ? W.accent.opacity(0.15) : W.border, padding: 9)
    }
}

struct SearchView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var tab = "movies"
    @State private var browseGenre: String?
    @State private var movieResults: [Movie] = []
    @State private var searching = false
    @State private var backendUsers: [(String, UserProfile)] = []
    @State private var suggested: [String]?
    @State private var showFindFriends = false
    @FocusState private var focused: Bool

    private let browse = [("🎭 Drama", "Drama"), ("🚀 Sci-Fi", "Sci-Fi"), ("😱 Horror", "Horror"), ("😂 Comedy", "Comedy"), ("💥 Action", "Action"), ("🌏 International", "international")]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if browseGenre != nil {
                    Button { browseGenre = nil } label: { Image(systemName: "chevron.left").foregroundStyle(W.text) }
                }
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(W.dim)
                    TextField(tab == "users" ? "Search users by name..." : "Search movies, directors...", text: $query)
                        .focused($focused)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit { store.addSearchHistory(query) }
                        .mono(12).foregroundStyle(W.text)
                        .accessibilityIdentifier("search-field")
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(W.dim) } }
                }
                .card(radius: 12, padding: 10)
            }
            .padding(.horizontal, 18).padding(.top, 8)
            UnderlineTabs(tabs: [("movies", "🎬 Movies"), ("users", "👥 Users")], selection: $tab)
                .padding(.horizontal, 18).padding(.vertical, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if tab == "movies" { moviesTab } else { usersTab }
                }
                .padding(.horizontal, 18).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(W.bg)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: tab) { browseGenre = nil }
        .task(id: query + tab) {
            guard query.count >= 2 else { movieResults = []; backendUsers = []; searching = false; return }
            searching = true
            try? await Task.sleep(for: .milliseconds(tab == "users" ? 250 : 400))
            guard !Task.isCancelled else { return }
            if tab == "movies" {
                movieResults = await Catalog.shared.search(query)
            } else if let rows = await APIClient.shared.searchUsers(query) {
                backendUsers = rows.map { u in
                    let name = u.username ?? String(u.user_id.prefix(8))
                    return ("@\(name)", UserProfile(username: name, avatar: String((u.name ?? name).prefix(1)).uppercased(), moviesRated: 0, streak: 0,
                                                    badge: "", bio: "", followers: u.follower_count ?? 0, following: u.following_count ?? 0, isPrivate: u.is_private ?? false))
                }
            }
            searching = false
            try? await Task.sleep(for: .milliseconds(800))
            if !Task.isCancelled { store.addSearchHistory(query) }
        }
        .onAppear {
            if suggested == nil {
                suggested = Array(Mock.profileOrder.sorted { (store.followingHandles.contains($0) ? 1 : 0) < (store.followingHandles.contains($1) ? 1 : 0) }.prefix(5))
            }
        }
        .sheet(isPresented: $showFindFriends) { FindFriendsSheet().presentationDetents([.medium]) }
    }

    @ViewBuilder
    private var moviesTab: some View {
        if query.count >= 2 {
            if searching && movieResults.isEmpty { ProgressView("Searching…").frame(maxWidth: .infinity).padding() }
            ForEach(movieResults) { movieRow($0) }
            if !searching && movieResults.isEmpty { Text("No results for \"\(query)\"").mono(10).foregroundStyle(W.dim).frame(maxWidth: .infinity).padding() }
        } else if let g = browseGenre {
            let results = (Mock.movies).filter { g == "international" ? $0.isInternational : $0.genres.contains(g) }
            SectionLabel(text: "\(browse.first { $0.1 == g }?.0 ?? g) · \(results.count) films")
            ForEach(results) { movieRow($0) }
            if results.isEmpty { Text("No movies in catalog yet").mono(10).foregroundStyle(W.dim) }
        } else {
            if !store.searchHistory.isEmpty {
                HStack {
                    SectionLabel(text: "RECENT SEARCHES")
                    Button("Clear") { Haptics.light(); store.searchHistory = [] }.mono(9, .bold).foregroundStyle(W.accent)
                }
                ForEach(store.searchHistory.prefix(6), id: \.self) { q in
                    HStack {
                        Button { query = q } label: {
                            HStack(spacing: 8) { T("🕒"); Text(q).mono(11).foregroundStyle(W.text); Spacer() }.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button { store.searchHistory.removeAll { $0 == q } } label: { Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(W.dim) }
                            .accessibilityLabel("Remove \(q) from search history")
                    }
                    .padding(.vertical, 4)
                }
            }
            SectionLabel(text: "TRENDING").padding(.top, 6)
            ForEach(Mock.movies.sorted { ($0.trendingRank ?? 99) < ($1.trendingRank ?? 99) }.prefix(5)) { m in
                NavigationLink(value: Route.movie(m)) {
                    HStack(spacing: 8) {
                        T("🔥")
                        Text(m.title).mono(12, .semibold).foregroundStyle(W.text)
                        if m.isInternational, let l = m.originalLanguage { BadgeView(text: l, color: .purple) }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(W.dim)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            SectionLabel(text: "BROWSE").padding(.top, 6)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(browse, id: \.1) { label, g in
                    Button { Haptics.light(); browseGenre = g } label: {
                        T(label).mono(11, .semibold).foregroundStyle(W.text).frame(maxWidth: .infinity).card(radius: 12, padding: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func movieRow(_ m: Movie) -> some View {
        NavigationLink(value: Route.movie(m)) {
            HStack(spacing: 12) {
                PosterView(url: m.posterURL, title: m.title, width: 36, height: 50, radius: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.title).mono(12, .bold).foregroundStyle(W.text).lineLimit(1)
                    Text([m.releaseYear.map(String.init), m.directors.first].compactMap { $0 }.joined(separator: " · ")).mono(9).foregroundStyle(W.dim)
                }
                Spacer()
                Text("#\(m.globalRank.map(String.init) ?? "—")").mono(10, .bold).foregroundStyle(W.dim)
            }
            .card(radius: 12, padding: 8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("result-\(m.id)")
    }

    @ViewBuilder
    private var usersTab: some View {
        Button { showFindFriends = true } label: {
            HStack(spacing: 12) {
                T("👋").font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Find your friends").mono(12, .bold).foregroundStyle(W.text)
                    Text("Connect contacts · or share an invite").mono(9).foregroundStyle(W.dim)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(W.dim)
            }
            .card(radius: 12, fill: W.accentDim, stroke: W.accent.opacity(0.3), padding: 12)
        }
        .buttonStyle(.plain)
        if query.count >= 2 {
            let needle = query.lowercased()
            let local = Mock.profileOrder.compactMap { h in Mock.profiles[h].map { (h, $0) } }
                .filter { $0.0.lowercased().contains(needle) || $0.1.bio.lowercased().contains(needle) }
            let seen = Set(backendUsers.map { $0.0.lowercased() })
            let results = backendUsers + local.filter { !seen.contains($0.0.lowercased()) }
            ForEach(results, id: \.0) { h, p in userRow(h, p) }
            if results.isEmpty && !searching { Text("No users matching \"\(query)\"").mono(10).foregroundStyle(W.dim).frame(maxWidth: .infinity).padding() }
        } else {
            SectionLabel(text: "SUGGESTED FOR YOU").padding(.top, 6)
            ForEach(suggested ?? [], id: \.self) { h in if let p = Mock.profiles[h] { userRow(h, p) } }
        }
    }

    private func userRow(_ h: String, _ p: UserProfile) -> some View {
        HStack(spacing: 10) {
            NavigationLink(value: Route.user(h)) {
                HStack(spacing: 10) {
                    AvatarView(initial: p.avatar, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(h).mono(12, .bold).foregroundStyle(W.text)
                            T(p.badge)
                            if p.isPrivate { T("🔒").font(.system(size: 9)) }
                        }
                        if !p.bio.isEmpty { Text(p.bio).mono(9).foregroundStyle(W.dim).lineLimit(1) }
                        Text("\(p.moviesRated) ranked · \(p.followers) followers").mono(8).foregroundStyle(W.dim)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            FollowPill(following: store.followingHandles.contains(h)) { store.toggleFollow(h) }
                .accessibilityIdentifier("follow-\(h)")
        }
        .card(radius: 12, padding: 10)
    }
}
