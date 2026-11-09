import SwiftUI

/// Own profile (ProfileScreen.jsx). Built on List so saved rows get swipe-to-remove.
struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @State private var tab = "rankings"
    @State private var savedGenre = "All"
    @State private var editingReview: UserReview?
    @State private var deletingReview: UserReview?

    private var rankings: [Movie] { store.rankedIds.compactMap { Catalog.shared.find($0) } }

    var body: some View {
        List {
            Group {
                header
                statsRow
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
        .navigationTitle("My Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.settings(nil)) { Text("Settings") }
                    .accessibilityIdentifier("open-settings")
            }
        }
        .refreshable { await store.hydrate() }
        .alert("Delete this review?", isPresented: Binding(get: { deletingReview != nil }, set: { if !$0 { deletingReview = nil } }), presenting: deletingReview) { r in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { store.deleteReview(r); store.showToast("Review deleted") }
        } message: { _ in Text("This will remove your review. This can't be undone.") }
        .sheet(item: $editingReview) { r in
            ReviewSheet(movie: Catalog.shared.find(r.movieId, title: r.movieTitle)!, existing: r)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AvatarView(initial: store.avatarInitial, size: 64)
                .background(NavigationLink(value: Route.settings(.account)) { EmptyView() }.opacity(0))
            VStack(alignment: .leading, spacing: 3) {
                if !store.displayName.isEmpty { Text(store.displayName).font(.headline).foregroundStyle(W.text) }
                Text("@\(store.username)").font(.subheadline).foregroundStyle(W.dim)
            }
            Spacer()
        }
        .padding(.top, 6)
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            stat(rankings.count, "Ranked")
            stat(store.savedMovies.count, "Saved")
        }
    }

    private func stat(_ n: Int, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.title3.weight(.semibold)).foregroundStyle(W.text).contentTransition(.numericText())
            Text(l).font(.subheadline).foregroundStyle(W.dim)
        }
        .frame(maxWidth: .infinity)
        .card(radius: 10, padding: 8)
        .accessibilityIdentifier("stat-\(l.lowercased())")
    }

    @ViewBuilder
    private var rankingsSection: some View {
        SectionLabel(text: "Your Rankings · \(rankings.count) films")
        if rankings.isEmpty { EmptyStateView(title: "No rankings yet", subtitle: "Open any movie and tap Rank") }
        ForEach(Array(rankings.enumerated()), id: \.element.id) { i, m in
            rankingRow(m, displayIndex: i)
        }
    }

    private func rankingRow(_ m: Movie, displayIndex: Int) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: Medal.label(displayIndex)).font(.subheadline.weight(.semibold)).foregroundStyle(W.dim).frame(minWidth: 24)
            PosterView(url: m.posterURL, title: m.title, width: 28, height: 38, radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.title).font(.headline).foregroundStyle(W.text).lineLimit(1)
            }
            Spacer()
            Text(verbatim: "\(store.eloScores[m.id] ?? 1500)").font(.subheadline.weight(.semibold)).foregroundStyle(W.blue)
        }
        .card(radius: 12, fill: displayIndex == 0 ? W.goldDim : W.card, padding: 8)
        .background(NavigationLink(value: Route.movie(m)) { EmptyView() }.opacity(0))
        .accessibilityIdentifier("ranking-\(m.id)")
    }

    @ViewBuilder
    private var savedSection: some View {
        let savedObjs = store.savedMovies.compactMap { Catalog.shared.find($0) }.sorted { $0.id < $1.id }
        let genres = ["All"] + Array(Set(savedObjs.flatMap(\.genres))).sorted()
        let filtered = savedGenre == "All" ? savedObjs : savedObjs.filter { $0.genres.contains(savedGenre) }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) { ForEach(genres, id: \.self) { g in Chip(label: g, selected: savedGenre == g) { savedGenre = g } } }
        }
        if !filtered.isEmpty { SectionLabel(text: "SAVED · \(filtered.count)") }
        if filtered.isEmpty { EmptyStateView(title: "Nothing saved yet", subtitle: "Save a movie to see it here") }
        ForEach(filtered) { m in
            savedRow(m, trailing: ("Saved", W.blue), sub: [m.releaseYear.map(String.init), m.directors.first].compactMap { $0 }.joined(separator: " · "))
                .swipeActions { Button("Remove", role: .destructive) { store.toggleSaved(m) } }
        }
    }

    private func savedRow(_ m: Movie, trailing: (String, Color), sub: String) -> some View {
        HStack(spacing: 12) {
            PosterView(url: m.posterURL, title: m.title, width: 36, height: 50, radius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.title).font(.headline).foregroundStyle(W.text).lineLimit(1)
                Text(sub).font(.subheadline).foregroundStyle(W.dim)
            }
            Spacer()
            Text(trailing.0).font(.subheadline.weight(.semibold)).foregroundStyle(trailing.1)
        }
        .card(radius: 12, padding: 8)
        .background(NavigationLink(value: Route.movie(m)) { EmptyView() }.opacity(0))
    }

    @ViewBuilder
    private var reviewsSection: some View {
        SectionLabel(text: "\(store.userReviews.count) REVIEWS · MOST RECENT FIRST")
        if store.userReviews.isEmpty { EmptyStateView(title: "No reviews yet", subtitle: "Open any movie and tap Review") }
        ForEach(store.userReviews) { r in
            reviewCard(movieId: r.movieId, title: r.movieTitle, score: r.rating, text: r.text,
                       tag: r.edited ? "edited" : nil, time: TimeFmt.relative(r.ts), own: r)
        }
    }

    private func reviewCard(movieId: String, title: String, score: Int, text: String, tag: String?, time: String, own: UserReview?) -> some View {
        let m = Catalog.shared.find(movieId, title: title)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                PosterView(url: m?.posterURL, title: title, width: 32, height: 44, radius: 6)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.headline).foregroundStyle(W.text).lineLimit(1)
                        if let t = tag { BadgeView(text: t, color: t == "NEW" ? .green : .blue) }
                    }
                    Text("\(score)/10").font(.subheadline.weight(.semibold)).foregroundStyle(W.gold)
                }
                Spacer()
                Text(time).font(.subheadline).foregroundStyle(W.dim)
                if let own {
                    Menu {
                        Button("Edit") { editingReview = own }
                        Button("Delete", role: .destructive) { deletingReview = own }
                    } label: { Text("More").font(.subheadline).foregroundStyle(W.dim) }
                    .accessibilityLabel("Review options")
                }
            }
            Text(text).font(.body).foregroundStyle(W.text.opacity(0.9)).lineSpacing(2)
        }
        .card(radius: 12, padding: 12)
        .background(Group { if let m { NavigationLink(value: Route.movie(m)) { EmptyView() }.opacity(0) } })
    }
}
