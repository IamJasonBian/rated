import SwiftUI

struct LeaderboardView: View {
    @State private var loaded = false
    @State private var topRated: [Movie]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Leaderboard").font(.title2.weight(.bold)).foregroundStyle(W.text).padding(.top, 6)
                if !loaded {
                    ProgressView("Loading top rated films...").font(.subheadline).frame(maxWidth: .infinity).padding(30)
                } else if let list = topRated {
                    if list.isEmpty { EmptyStateView(title: "No rankings yet", subtitle: "Rank a movie to start the board") }
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, m in
                        NavigationLink(value: Route.movie(m)) {
                            movieRow(m, index: i, sub: m.releaseYear.map(String.init) ?? "",
                                     value: "\(m.avgUserRating.map { String(format: "%.1f", $0) } ?? "—")", unit: "Avg")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("top-\(m.id)")
                    }
                } else {
                    EmptyStateView(title: "Couldn't load the leaderboard", subtitle: "Pull down to try again")
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 24)
        }
        .background(W.bg)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await load() }
        .task { if !loaded { await load() } }
    }

    private func load() async {
        topRated = await Catalog.shared.topRated()
        loaded = true
    }

    private func movieRow(_ m: Movie, index i: Int, sub: String, value: String, unit: String) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: Medal.label(i)).font(.subheadline.weight(.semibold)).foregroundStyle(W.dim).frame(minWidth: 24)
            PosterView(url: m.posterURL, title: m.title, width: 32, height: 44, radius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.title).font(.headline).foregroundStyle(W.text).lineLimit(1)
                Text(sub).font(.subheadline).foregroundStyle(W.dim).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(value).font(.headline).foregroundStyle(W.gold)
                Text(unit).font(.subheadline).foregroundStyle(W.dim)
            }
        }
        .card(radius: 12, fill: i < 3 ? W.accent.opacity(0.04) : W.card, stroke: i < 3 ? W.accent.opacity(0.15) : W.border, padding: 8)
    }
}

struct SearchView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var movieResults: [Movie] = []
    @State private var searching = false
    @State private var failed = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    TextField("Search movies, directors...", text: $query)
                        .focused($focused)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit { store.addSearchHistory(query) }
                        .font(.body).foregroundStyle(W.text)
                        .accessibilityIdentifier("search-field")
                    if !query.isEmpty { Button { query = "" } label: { Text("Clear").font(.subheadline).foregroundStyle(W.dim) }.hitArea() }
                }
                .card(radius: 12, padding: 10)
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    moviesTab
                }
                .padding(.horizontal, 18).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(W.bg)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: query) {
            guard query.count >= 2 else { movieResults = []; searching = false; failed = false; return }
            searching = true
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let results = await Catalog.shared.search(query)
            failed = results == nil
            movieResults = results ?? []
            searching = false
            try? await Task.sleep(for: .milliseconds(800))
            if !Task.isCancelled { store.addSearchHistory(query) }
        }
    }

    @ViewBuilder
    private var moviesTab: some View {
        if query.count >= 2 {
            if searching && movieResults.isEmpty { ProgressView("Searching…").frame(maxWidth: .infinity).padding() }
            ForEach(movieResults) { movieRow($0) }
            if !searching && failed {
                EmptyStateView(title: "Couldn't search right now", subtitle: "Check your connection and try again")
            } else if !searching && movieResults.isEmpty {
                Text("No results for \"\(query)\"").font(.subheadline).foregroundStyle(W.dim).frame(maxWidth: .infinity).padding()
            }
        } else if !store.searchHistory.isEmpty {
            HStack {
                SectionLabel(text: "Recent Searches")
                Button("Clear") { Haptics.light(); store.searchHistory = [] }.font(.subheadline.weight(.semibold)).foregroundStyle(W.accent)
            }
            ForEach(store.searchHistory.prefix(6), id: \.self) { q in
                HStack {
                    Button { query = q } label: {
                        HStack(spacing: 8) { Text(q).font(.subheadline).foregroundStyle(W.text); Spacer() }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { store.searchHistory.removeAll { $0 == q } } label: { Text("Remove").font(.subheadline).foregroundStyle(W.dim) }
                        .hitArea()
                        .accessibilityLabel("Remove \(q) from search history")
                }
                .padding(.vertical, 4)
            }
        } else {
            EmptyStateView(title: "Search for a movie", subtitle: "Type at least two letters")
        }
    }

    private func movieRow(_ m: Movie) -> some View {
        NavigationLink(value: Route.movie(m)) {
            HStack(spacing: 12) {
                PosterView(url: m.posterURL, title: m.title, width: 36, height: 50, radius: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.title).font(.headline).foregroundStyle(W.text).lineLimit(1)
                    Text([m.releaseYear.map(String.init), m.directors.first].compactMap { $0 }.joined(separator: " · ")).font(.subheadline).foregroundStyle(W.dim)
                }
                Spacer()
            }
            .card(radius: 12, padding: 8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("result-\(m.id)")
    }
}
