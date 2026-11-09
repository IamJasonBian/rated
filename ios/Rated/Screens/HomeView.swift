import SwiftUI

/// Popular films from the catalog (HomeScreen.jsx highlights).
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @State private var loaded = false
    @State private var highlights: [Movie] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                if !loaded {
                    skeleton
                } else if highlights.isEmpty {
                    errorBanner
                } else {
                    SectionLabel(text: "Highlights")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 10)], spacing: 14) {
                        ForEach(highlights) { m in highlightCard(m) }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(W.bg)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { Catalog.shared.invalidate(); await load() }
        .task {
            guard !loaded else { return }
            await load()
            withAnimation { loaded = true }
        }
    }

    private func load() async {
        highlights = await Catalog.shared.popular()
    }

    private var header: some View {
        HStack {
            Text("Rated").font(.title2.weight(.bold)).foregroundStyle(W.text)
            Spacer()
        }
        .padding(.top, 6)
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBlock(width: 90, height: 11)
            HStack(spacing: 10) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(width: 105, height: 148, radius: 12) } }
        }
    }

    private var errorBanner: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't load movies").font(.subheadline.weight(.semibold)).foregroundStyle(W.text)
                Text("Check your connection and try again.").font(.subheadline).foregroundStyle(W.dim)
            }
            Spacer()
            Button("Retry") { Task { loaded = false; await load(); loaded = true } }.font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("home-retry")
        }
        .card(radius: 12, fill: W.orangeDim, stroke: W.orange.opacity(0.4), padding: 10)
    }

    private func highlightCard(_ m: Movie) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NavigationLink(value: Route.movie(m)) {
                PosterView(url: m.posterURL, title: m.title, width: 105, height: 148, radius: 12)
                    .overlay(alignment: .topLeading) {
                        if let r = m.trendingRank, r <= 3 {
                            Text("#\(r)").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(W.accent)).padding(6)
                        }
                    }
            }
            .accessibilityIdentifier("highlight-\(m.id)")
            VStack(alignment: .leading, spacing: 4) {
                Text(m.title).font(.subheadline.weight(.semibold)).foregroundStyle(W.text).lineLimit(1)
                Button { store.toggleSaved(m) } label: {
                    Text(store.savedMovies.contains(m.id) ? "Saved" : "Save").font(.subheadline).foregroundStyle(store.savedMovies.contains(m.id) ? W.blue : W.dim)
                }
                .hitArea()
                .accessibilityLabel(store.savedMovies.contains(m.id) ? "Unsave \(m.title)" : "Save \(m.title)")
            }
            .frame(width: 105)
        }
    }
}
