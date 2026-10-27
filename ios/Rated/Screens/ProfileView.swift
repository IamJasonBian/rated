import SwiftUI

/// Own profile (ProfileScreen.jsx). Built on List so rankings get native
/// drag-to-reorder in edit mode and saved/watchlist rows get swipe-to-remove.
struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @State private var tab = "rankings"
    @State private var rankSort = "ranked"
    @State private var savedSort = "default"
    @State private var savedGenre = "All"
    @State private var editMode: EditMode = .inactive
    @State private var unrankConfirm: Movie?
    @State private var social: String?
    @State private var showImport = false
    @State private var editingReview: UserReview?
    @State private var deletingReview: UserReview?

    private var rankings: [Movie] { store.rankedIds.compactMap { Catalog.shared.find($0) } }
    private var followers: [String] {
        var s = Set(Mock.friends.filter { $0.followsMe || store.followingHandles.contains("@\($0.username)") }.map { "@\($0.username)" })
        s.formUnion(store.approvedFollowers)
        return s.sorted()
    }

    var body: some View {
        List {
            Group {
                header
                statsRow
                buttonsRow
                UnderlineTabs(tabs: [("rankings", "Rankings"), ("saved", "Saved"), ("reviews", "Reviews")], selection: $tab)
                switch tab {
                case "rankings": rankingsSection
                case "saved": savedSection
                default: reviewsSection
                }
            }
            .listRowBackground(W.bg)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(W.bg)
        .environment(\.editMode, $editMode)
        .navigationTitle("MY PROFILE")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Text("MY PROFILE").mono(13, .heavy).foregroundStyle(W.text) }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.settings(nil)) { Image(systemName: "gearshape") }
                    .accessibilityIdentifier("open-settings")
            }
        }
        .refreshable { await store.hydrate() }
        .alert("Remove from rankings?", isPresented: Binding(get: { unrankConfirm != nil }, set: { if !$0 { unrankConfirm = nil } }), presenting: unrankConfirm) { m in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { store.unrank(m.id) }
        } message: { m in
            Text("\(m.title) will be removed from your rankings and its ELO score deleted. You can re-rank it anytime.")
        }
        .alert("Delete this review?", isPresented: Binding(get: { deletingReview != nil }, set: { if !$0 { deletingReview = nil } }), presenting: deletingReview) { r in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { store.deleteReview(r); store.showToast("Review deleted") }
        } message: { _ in Text("This will remove your review and the corresponding activity from your feed. This can't be undone.") }
        .sheet(item: Binding(get: { social.map(IdentifiableString.init) }, set: { social = $0?.value })) { s in
            SocialListSheet(kind: s.value, handles: s.value == "following" ? store.followingHandles.sorted() : followers)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showImport) { ImportInfoSheet().presentationDetents([.large]) }
        .sheet(item: $editingReview) { r in
            ReviewSheet(movie: Catalog.shared.find(r.movieId, title: r.movieTitle)!, existing: r)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            NavigationLink(value: Route.settings(.account)) {
                AvatarView(initial: store.avatarInitial, size: 64, image: store.profilePic)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil.circle.fill").font(.system(size: 18)).foregroundStyle(W.accent).background(Circle().fill(W.bg))
                    }
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                if !store.displayName.isEmpty { Text(store.displayName).mono(15, .black).foregroundStyle(W.text) }
                HStack(spacing: 6) {
                    Text("@\(store.username)").mono(11).foregroundStyle(W.dim)
                    if store.isPrivate { BadgeView(text: "🔒 Private", color: .purple) }
                }
                if !store.bio.isEmpty { Text(store.bio).mono(10).foregroundStyle(W.text.opacity(0.85)) }
                let s = store.streak
                HStack(spacing: 4) {
                    Text(s.status == .atRisk ? "⚠️" : "🔥")
                    Text("\(s.count)-week streak").mono(10, .bold).foregroundStyle(s.status == .active ? W.gold : s.status == .atRisk ? W.orange : W.dim)
                    if s.status == .atRisk { Text("· rank before Sunday").mono(9).foregroundStyle(W.orange) }
                }
                .accessibilityIdentifier("streak")
            }
            Spacer()
        }
        .padding(.top, 6)
    }

    private var statsRow: some View {
        let savedCount = store.savedMovies.count + store.watchlist.count
        return HStack(spacing: 8) {
            stat(rankings.count, "Ranked", nil)
            stat(savedCount, "Saved", nil)
            stat(store.followingHandles.count, "Following", "following")
            stat(followers.count, "Followers", "followers")
        }
    }

    private func stat(_ n: Int, _ l: String, _ click: String?) -> some View {
        Button { if let c = click { Haptics.light(); social = c } } label: {
            VStack(spacing: 2) {
                Text("\(n)").mono(16, .black).foregroundStyle(W.text).contentTransition(.numericText())
                Text(l).mono(8).foregroundStyle(W.dim)
            }
            .frame(maxWidth: .infinity)
            .card(radius: 10, padding: 8)
        }
        .buttonStyle(.borderless)
        .disabled(click == nil)
        .accessibilityIdentifier("stat-\(l.lowercased())")
    }

    private var buttonsRow: some View {
        HStack(spacing: 8) {
            NavigationLink(value: Route.settings(.account)) {
                Text("✎ Edit Profile").mono(10, .bold).foregroundStyle(W.text).frame(maxWidth: .infinity).card(radius: 10, padding: 9)
            }
            .buttonStyle(.borderless)
            ShareLink(item: ShareLinks.profile(store.username), subject: Text("\(store.username) on RATED")) {
                Label("Share Profile", systemImage: "square.and.arrow.up").mono(10, .bold).foregroundStyle(W.text).frame(maxWidth: .infinity).card(radius: 10, padding: 9)
            }
            .buttonStyle(.borderless)
        }
    }

    private func sortMenu(_ selection: Binding<String>, _ options: [(String, String)]) -> some View {
        Menu {
            Picker("Sort", selection: selection) { ForEach(options, id: \.0) { Text($0.1).tag($0.0) } }
        } label: {
            Text("\(options.first { $0.0 == selection.wrappedValue }?.1 ?? "") ▾").mono(9, .bold).foregroundStyle(W.dim)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(W.card)).overlay(Capsule().stroke(W.border))
        }
    }

    private func sortMovies(_ ms: [Movie], _ key: String) -> [Movie] {
        switch key {
        case "alpha": ms.sorted { $0.title < $1.title }
        case "popular": ms.sorted { ($0.avgUserRating ?? 0) > ($1.avgUserRating ?? 0) }
        case "unpopular": ms.sorted { ($0.avgUserRating ?? 0) < ($1.avgUserRating ?? 0) }
        default: ms
        }
    }

    @ViewBuilder
    private var rankingsSection: some View {
        let editing = editMode == .active
        HStack {
            SectionLabel(text: "YOUR RANKINGS · \(rankings.count) films")
            if !rankings.isEmpty {
                Button(editing ? "✓ Done" : "✎ Edit") {
                    Haptics.light()
                    withAnimation { editMode = editing ? .inactive : .active; if !editing { rankSort = "ranked" } }
                }
                .mono(9, .bold).foregroundStyle(W.accent).buttonStyle(.borderless)
                .accessibilityIdentifier("edit-rankings")
            }
            sortMenu($rankSort, [("ranked", "My Rank"), ("alpha", "A–Z"), ("popular", "Most Popular"), ("unpopular", "Least Popular")])
        }
        if rankings.isEmpty { EmptyStateView(icon: "🎬", title: "No rankings yet", subtitle: "Open any movie and tap ⚡ RANK") }
        let sorted = sortMovies(rankings, rankSort)
        ForEach(Array(sorted.enumerated()), id: \.element.id) { i, m in
            rankingRow(m, displayIndex: rankSort == "ranked" ? (store.rankedIds.firstIndex(of: m.id) ?? i) : i, editing: editing)
                .swipeActions(edge: .trailing) {
                    Button("Remove", systemImage: "trash") { unrankConfirm = m }.tint(W.accent)
                    Button("Re-rank", systemImage: "arrow.clockwise") { store.reRank(m) }.tint(W.blue)
                }
        }
        .onMove(perform: rankSort == "ranked" ? { store.moveRanking(from: $0, to: $1); Haptics.light() } : nil)
        importCard
    }

    private func rankingRow(_ m: Movie, displayIndex: Int, editing: Bool) -> some View {
        HStack(spacing: 10) {
            T(Medal.label(displayIndex)).mono(displayIndex < 3 ? 14 : 10, .black).foregroundStyle(W.dim).frame(width: 24)
            PosterView(url: m.posterURL, title: m.title, width: 28, height: 38, radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.title).mono(11, .bold).foregroundStyle(W.text).lineLimit(1)
                Text("\(m.releaseYear.map(String.init) ?? "")\(rankSort != "ranked" ? m.avgUserRating.map { " · ★ \($0) avg" } ?? "" : "")").mono(8).foregroundStyle(W.dim)
            }
            Spacer()
            if editing {
                Button { store.reRank(m) } label: { Image(systemName: "arrow.clockwise").foregroundStyle(W.blue) }
                    .buttonStyle(.borderless).accessibilityLabel("Re-rank \(m.title)")
                Button { unrankConfirm = m } label: { Image(systemName: "xmark").foregroundStyle(W.accent) }
                    .buttonStyle(.borderless).accessibilityLabel("Remove \(m.title)")
            } else {
                T("\(store.eloScores[m.id] ?? 1500)").mono(10, .bold).foregroundStyle(W.blue)
            }
        }
        .card(radius: 10, fill: displayIndex == 0 && rankSort == "ranked" ? W.goldDim : W.card, padding: 8)
        .background(NavigationLink(value: Route.movie(m)) { EmptyView() }.opacity(0).disabled(editing))
        .accessibilityIdentifier("ranking-\(m.id)")
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                T("📥 IMPORT YOUR DATA").mono(10, .black).foregroundStyle(W.text)
                BadgeView(text: "COMING SOON", color: .orange)
                Spacer()
                Button { showImport = true } label: { Image(systemName: "info.circle").foregroundStyle(W.dim) }.buttonStyle(.borderless)
            }
            Text("We're working on matching your imported history to our movie database. You'll be notified when it's ready.").mono(9).foregroundStyle(W.dim)
            ForEach([("🎬", "Letterboxd", "Upload diary.csv from letterboxd.com"), ("⭐", "IMDb", "Upload ratings.csv from imdb.com"),
                     ("📺", "Trakt", "Upload history.json from trakt.tv"), ("🔴", "Netflix", "Upload ViewingActivity.csv")], id: \.1) { icon, name, sub in
                HStack(spacing: 8) {
                    T(icon)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).mono(10, .bold).foregroundStyle(W.text)
                        Text(sub).mono(8).foregroundStyle(W.dim)
                    }
                    Spacer()
                    Text("SOON").mono(8, .bold).foregroundStyle(W.dim)
                }
                .opacity(0.7)
            }
        }
        .card(radius: 14, padding: 12)
        .padding(.top, 10)
    }

    @ViewBuilder
    private var savedSection: some View {
        let savedObjs = store.savedMovies.compactMap { Catalog.shared.find($0) }.filter { !$0.isUpcoming }.sorted { $0.id < $1.id }
        let watch = store.watchlist.compactMap { Catalog.shared.find($0) }.sorted { ($0.daysUntilRelease ?? 0) < ($1.daysUntilRelease ?? 0) }
        let genres = ["All"] + Array(Set(savedObjs.flatMap(\.genres))).sorted()
        let filtered = sortMovies(savedGenre == "All" ? savedObjs : savedObjs.filter { $0.genres.contains(savedGenre) }, savedSort)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) { ForEach(genres, id: \.self) { g in Chip(label: g, selected: savedGenre == g) { savedGenre = g } } }
        }
        if !filtered.isEmpty {
            HStack {
                SectionLabel(text: "SAVED · \(filtered.count)")
                sortMenu($savedSort, [("default", "Default"), ("alpha", "A–Z"), ("popular", "Most Popular"), ("unpopular", "Least Popular")])
            }
        }
        if filtered.isEmpty && watch.isEmpty { EmptyStateView(icon: "◇", title: "Nothing saved yet", subtitle: "Tap ◇ on any movie to save it") }
        ForEach(filtered) { m in
            savedRow(m, trailing: ("◆", "SAVED", W.blue), sub: [m.releaseYear.map(String.init), m.directors.first].compactMap { $0 }.joined(separator: " · "))
                .swipeActions { Button("Remove", systemImage: "trash", role: .destructive) { store.toggleSaved(m) } }
        }
        if !watch.isEmpty { SectionLabel(text: "WATCHLIST · \(watch.count)").padding(.top, 8) }
        ForEach(watch) { u in
            savedRow(u, trailing: ("◈", "SOON", W.orange), sub: "\(TimeFmt.releaseDate(u.releaseDate)) · \(TimeFmt.countdown(u.releaseDate))")
                .swipeActions { Button("Remove", systemImage: "trash", role: .destructive) { store.toggleWatchlist(u.id) } }
        }
    }

    private func savedRow(_ m: Movie, trailing: (String, String, Color), sub: String) -> some View {
        HStack(spacing: 12) {
            PosterView(url: m.posterURL, title: m.title, width: 36, height: 50, radius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.title).mono(12, .bold).foregroundStyle(W.text).lineLimit(1)
                Text(sub).mono(9).foregroundStyle(W.dim)
                if let a = m.avgUserRating { Text("★ \(String(format: "%.1f", a)) avg").mono(9).foregroundStyle(W.gold) }
            }
            Spacer()
            VStack(spacing: 1) {
                T(trailing.0).foregroundStyle(trailing.2)
                Text(trailing.1).mono(7, .bold).foregroundStyle(trailing.2)
            }
        }
        .card(radius: 12, padding: 8)
        .background(NavigationLink(value: Route.movie(m)) { EmptyView() }.opacity(0))
    }

    @ViewBuilder
    private var reviewsSection: some View {
        SectionLabel(text: "\(store.userReviews.count + Mock.profileReviews.count) REVIEWS · MOST RECENT FIRST")
        ForEach(store.userReviews) { r in
            reviewCard(movieId: r.movieId, title: r.movieTitle, score: r.rating, text: r.text,
                       tag: r.edited ? "edited" : "NEW", time: TimeFmt.relative(r.ts), own: r)
        }
        ForEach(Mock.profileReviews, id: \.id) { r in
            // Seeded reviews show a score derived from the movie's current position, like the web.
            let pos = store.rankedIds.firstIndex(of: r.movieId)
            let score = pos.map { Elo.score(position: $0 + 1, total: store.rankedIds.count) } ?? r.rating
            reviewCard(movieId: r.movieId, title: r.movieTitle, score: score, text: r.text, tag: nil, time: r.time, own: nil)
        }
    }

    private func reviewCard(movieId: String, title: String, score: Int, text: String, tag: String?, time: String, own: UserReview?) -> some View {
        let m = Catalog.shared.find(movieId, title: title)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                PosterView(url: m?.posterURL, title: title, width: 32, height: 44, radius: 6)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).mono(12, .bold).foregroundStyle(W.text).lineLimit(1)
                        if let t = tag { BadgeView(text: t, color: t == "NEW" ? .green : .blue) }
                    }
                    Text("\(score)/10").mono(11, .black).foregroundStyle(W.gold)
                }
                Spacer()
                Text(time).mono(8).foregroundStyle(W.dim)
                if let own {
                    Menu {
                        Button("Edit", systemImage: "pencil") { editingReview = own }
                        Button("Delete", systemImage: "trash", role: .destructive) { deletingReview = own }
                    } label: { Image(systemName: "ellipsis").foregroundStyle(W.dim).frame(width: 28, height: 28) }
                    .accessibilityLabel("Review options")
                }
            }
            Text(text).mono(10).foregroundStyle(W.text.opacity(0.9)).lineSpacing(2)
        }
        .card(radius: 12, padding: 12)
        .background(Group { if let m { NavigationLink(value: Route.movie(m)) { EmptyView() }.opacity(0) } })
    }
}

struct IdentifiableString: Identifiable { var value: String; var id: String { value } }

struct SocialListSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let kind: String
    let handles: [String]

    var body: some View {
        NavigationStack {
            List {
                if handles.isEmpty {
                    Text(kind == "following" ? "You're not following anyone yet" : "No followers yet").mono(11).foregroundStyle(W.dim)
                }
                ForEach(handles, id: \.self) { h in
                    let p = Mock.profiles[h] ?? .placeholder(for: h)
                    HStack(spacing: 10) {
                        AvatarView(initial: p.avatar, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(h).mono(12, .bold).foregroundStyle(W.text)
                            Text("\(p.moviesRated) films ranked").mono(9).foregroundStyle(W.dim)
                        }
                        Spacer()
                        FollowPill(following: store.followingHandles.contains(h)) { store.toggleFollow(h) }.buttonStyle(.borderless)
                    }
                    .listRowBackground(W.card)
                    .swipeActions {
                        if kind == "following" && store.followingHandles.contains(h) {
                            Button("Unfollow", role: .destructive) { store.toggleFollow(h) }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(W.bg)
            .navigationTitle(kind == "following" ? "Following · \(store.followingHandles.count)" : "Followers · \(handles.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct ImportInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let sources: [(String, String, [String])] = [
        ("🎬", "Letterboxd", ["Go to letterboxd.com → Settings", "Click Import & Export", "Click Export Your Data", "Download the ZIP and open diary.csv", "Tap IMPORT → on Rated and upload the CSV"]),
        ("⭐", "IMDb", ["Go to imdb.com → Your Ratings", "Click the 3-dot menu → Export", "Download the CSV file", "Tap IMPORT → on Rated and upload it"]),
        ("📺", "Trakt", ["Go to trakt.tv → Settings → Data", "Click Export Data", "Download history.json", "Tap IMPORT → on Rated and upload it"]),
        ("🔴", "Netflix", ["Go to netflix.com → Account", "Click Get My Info under Privacy", "Download ViewingActivity.csv", "Tap IMPORT → on Rated and upload it"]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                T("📥 HOW TO IMPORT").mono(14, .black).foregroundStyle(W.text)
                ForEach(sources, id: \.1) { icon, name, steps in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(icon) \(name)").mono(12, .bold).foregroundStyle(W.text)
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                            Text("\(i + 1). \(s)").mono(10).foregroundStyle(W.dim)
                        }
                    }
                    .card(radius: 12, padding: 12)
                }
                RatedButton(title: "GOT IT") { dismiss() }
            }
            .padding(20)
        }
        .background(W.bg)
    }
}

/// Another user's profile with private-account lock wall (UserProfileScreen.jsx).
struct UserProfileView: View {
    @Environment(AppStore.self) private var store
    let handle: String
    @State private var requested = false
    @State private var confirmUnfollow = false
    @State private var tab = "rankings"

    var body: some View {
        let p = Mock.profiles[handle] ?? .placeholder(for: handle)
        let following = store.followingHandles.contains(handle)
        let canSee = !p.isPrivate || following
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if store.blockedUsers.contains(handle) {
                    VStack(alignment: .leading, spacing: 2) {
                        T("🚫 You blocked this user").mono(11, .bold).foregroundStyle(W.accent)
                        Text("Unblock them in Settings → Privacy to see their content.").mono(9).foregroundStyle(W.dim)
                    }
                    .card(radius: 12, fill: W.accentDim, stroke: W.accent.opacity(0.3), padding: 10)
                }
                HStack(spacing: 14) {
                    AvatarView(initial: p.avatar, size: 60)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("@\(p.username)").mono(15, .black).foregroundStyle(W.text)
                            T(p.badge)
                            if p.isPrivate { BadgeView(text: "🔒 Private", color: .purple) }
                        }
                        if !p.bio.isEmpty { Text(p.bio).mono(10).foregroundStyle(W.text.opacity(0.85)) }
                        if p.streak > 0 { T("🔥 \(p.streak)-week streak").mono(10, .bold).foregroundStyle(W.gold) }
                    }
                }
                HStack(spacing: 8) {
                    ForEach([(canSee ? "\(p.moviesRated)" : "—", "Ranked"), ("\(p.followers + (following ? 1 : 0))", "Followers"), (canSee ? "\(p.following)" : "—", "Following")], id: \.1) { n, l in
                        VStack(spacing: 2) { T(n).mono(16, .black).foregroundStyle(W.text); Text(l).mono(8).foregroundStyle(W.dim) }
                            .frame(maxWidth: .infinity).card(radius: 10, padding: 8)
                    }
                }
                RatedButton(title: following ? "✓ FOLLOWING" : requested ? "⏳ REQUESTED — tap to cancel" : "+ FOLLOW",
                            style: following ? .outline : requested ? .tinted(W.orange) : .accent) {
                    if following { confirmUnfollow = true }
                    else if p.isPrivate { if requested { requested = false } else if let msg = store.followLimitMessage() { store.showToast(msg, .error) } else { Haptics.light(); requested = true } }
                    else { store.toggleFollow(handle) }
                }
                .accessibilityIdentifier("profile-follow")
                if !canSee {
                    VStack(spacing: 6) {
                        T("🔒").font(.system(size: 32))
                        Text("This account is private").mono(13, .bold).foregroundStyle(W.text)
                        Text("Follow @\(p.username) to see their rankings, reviews, and activity.").mono(10).foregroundStyle(W.dim).multilineTextAlignment(.center)
                        if requested { Text("Follow request sent — waiting for approval").mono(9, .bold).foregroundStyle(W.orange) }
                    }
                    .frame(maxWidth: .infinity).card(radius: 14, padding: 24)
                } else {
                    UserContentTabs(handle: handle, profile: p, tab: $tab)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 8)
        }
        .background(W.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ReportBlockMenu(targetType: "user", targetId: handle, targetLabel: handle, targetUser: handle) } }
        .alert("Unfollow \(handle)?", isPresented: $confirmUnfollow) {
            Button("Cancel", role: .cancel) {}
            Button("Unfollow", role: .destructive) { store.toggleFollow(handle); requested = false }
        } message: { Text("You'll stop seeing their posts in your Following feed. You can follow again anytime.") }
    }
}

/// Deterministic per-handle mock content until real per-user endpoints land.
private struct UserContentTabs: View {
    let handle: String
    let profile: UserProfile
    @Binding var tab: String

    var body: some View {
        let seed = charSum(handle)
        let all = Mock.movies
        let count = min(profile.moviesRated, all.count)
        let rankings = (0..<count).map { all[(seed % all.count + $0) % all.count] }
        let reviewed = Array(rankings.prefix(min(2, max(1, seed % 3))))
        let texts = ["Absolutely floored. Direction, score, everything clicked.", "Overhyped in my opinion but still a solid watch.",
                     "Couldn't look away. One of the best I've seen this year.", "The third act drags but the payoff makes it worthwhile.",
                     "Not sure what all the fuss is about. Rewatched to be sure."]
        let rating: (Int) -> Int = { i in max(5, 10 - Int(Double(i) / max(Double(rankings.count) / 6, 1))) }
        VStack(alignment: .leading, spacing: 8) {
            UnderlineTabs(tabs: [("rankings", "Rankings · \(rankings.count)"), ("reviews", "Reviews · \(reviewed.count)"), ("activity", "Activity")], selection: $tab)
            switch tab {
            case "rankings":
                if rankings.isEmpty { EmptyStateView(icon: "🎬", title: "No rankings yet", subtitle: "@\(profile.username) hasn't ranked any films") }
                ForEach(Array(rankings.enumerated()), id: \.element.id) { i, m in
                    NavigationLink(value: Route.movie(m)) {
                        HStack(spacing: 10) {
                            T(Medal.label(i)).mono(i < 3 ? 14 : 10, .black).foregroundStyle(W.dim).frame(width: 24)
                            PosterView(url: m.posterURL, title: m.title, width: 28, height: 38, radius: 4)
                            VStack(alignment: .leading) {
                                Text(m.title).mono(11, .bold).foregroundStyle(W.text)
                                Text(m.releaseYear.map(String.init) ?? "").mono(8).foregroundStyle(W.dim)
                            }
                            Spacer()
                            Text("\(rating(i))/10").mono(11, .black).foregroundStyle(W.gold)
                        }
                        .card(radius: 10, padding: 8)
                    }
                    .buttonStyle(.plain)
                }
            case "reviews":
                ForEach(Array(reviewed.enumerated()), id: \.element.id) { i, m in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            PosterView(url: m.posterURL, title: m.title, width: 32, height: 44, radius: 6)
                            VStack(alignment: .leading) {
                                Text(m.title).mono(12, .bold).foregroundStyle(W.text)
                                Text("\(rating(i))/10").mono(11, .black).foregroundStyle(W.gold)
                            }
                            Spacer()
                            Text(i == 0 ? "3d ago" : "1w ago").mono(8).foregroundStyle(W.dim)
                        }
                        Text(texts[(seed + i) % texts.count]).mono(10).foregroundStyle(W.text.opacity(0.9))
                    }
                    .card(radius: 12, padding: 12)
                }
            default:
                ForEach(Array(zip(["ranked a new film", "posted a review", "ranked a new film", "saved to watchlist"], ["2d ago", "4d ago", "1w ago", "2w ago"]).enumerated()), id: \.offset) { i, pair in
                    if i < rankings.count {
                        let m = i == 1 ? (reviewed.first ?? rankings[0]) : rankings[min(i == 0 ? 0 : i - 1, rankings.count - 1)]
                        NavigationLink(value: Route.movie(m)) {
                            HStack(spacing: 10) {
                                PosterView(url: m.posterURL, title: m.title, width: 26, height: 36, radius: 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(Text("@\(profile.username)").bold()) \(pair.0)").mono(10).foregroundStyle(W.text)
                                    Text(m.title).mono(10, .bold).foregroundStyle(W.accent)
                                }
                                Spacer()
                                Text(pair.1).mono(8).foregroundStyle(W.dim)
                            }
                            .card(radius: 12, padding: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
