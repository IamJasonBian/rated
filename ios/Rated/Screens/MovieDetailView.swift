import SwiftUI

/// Movie detail (MovieDetailScreen.jsx): backdrop, trailer, rating,
/// rank/save/review actions and cast.
struct MovieDetailView: View {
    @Environment(AppStore.self) private var store
    let movie: Movie
    @State private var m: Movie?
    @State private var showReview = false
    @State private var trailerURL: IdentifiableURL?
    @State private var viewerURL: IdentifiableURL?
    @State private var synopsisExpanded = false

    var body: some View {
        let m = self.m ?? movie
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(m)
                VStack(alignment: .leading, spacing: 14) {
                    titleBlock(m)
                    statsRow(m)
                    if !m.genres.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(m.genres, id: \.self) { g in
                                    Text(g).font(.subheadline.weight(.semibold)).foregroundStyle(W.dim)
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(Capsule().fill(W.card)).overlay(Capsule().stroke(W.border))
                                }
                            }
                        }
                    }
                    if !m.synopsis.isEmpty {
                        Text(m.synopsis).font(.body).foregroundStyle(W.text.opacity(0.85)).lineSpacing(3)
                            .lineLimit(synopsisExpanded ? nil : 4)
                            .onTapGesture { withAnimation { synopsisExpanded.toggle() } }
                    }
                    actionRow(m)
                    if !m.cast.isEmpty { castRow(m) }
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 30)
            }
        }
        .background(W.bg)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showReview) { ReviewSheet(movie: m, existing: nil).presentationDetents([.large]) }
        .sheet(item: $trailerURL) { SafariView(url: $0.url).ignoresSafeArea() }
        .fullScreenCover(item: $viewerURL) { ImageViewer(url: $0.url) }
        .task(id: movie.id) { self.m = await Catalog.shared.detail(movie) }
    }

    private func hero(_ m: Movie) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let b = m.backdropURL ?? m.posterURL, let u = URL(string: b) {
                    AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { W.card }
                        .onTapGesture { Haptics.light(); viewerURL = IdentifiableURL(url: u) }
                } else {
                    LinearGradient(colors: [W.accent.opacity(0.3), W.bg], startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(height: 260).frame(minWidth: 0, maxWidth: .infinity).clipped()
            LinearGradient(colors: [.clear, W.bg], startPoint: .center, endPoint: .bottom).allowsHitTesting(false)
            HStack(alignment: .bottom) {
                PosterView(url: m.posterURL, title: m.title, width: 76, height: 106, radius: 10)
                    .shadow(radius: 10)
                    .onTapGesture { if let p = m.posterURL, let u = URL(string: p) { viewerURL = IdentifiableURL(url: u) } }
                Spacer()
                if let t = m.primaryTrailer {
                    Button {
                        Haptics.medium()
                        trailerURL = URL(string: "https://www.youtube.com/watch?v=\(t.videoKey)").map(IdentifiableURL.init)
                    } label: {
                        HStack(spacing: 6) {
                            Text("Play Trailer").font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(.black.opacity(0.6)))
                        .overlay(Capsule().stroke(.white.opacity(0.3)))
                    }
                    .accessibilityIdentifier("play-trailer")
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 2)
        }
        .frame(height: 260)
    }

    private func titleBlock(_ m: Movie) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(m.title).font(.title2.weight(.bold)).foregroundStyle(W.text)
                    .accessibilityIdentifier("detail-title")
                if m.isInternational, let l = m.originalLanguage { BadgeView(text: l.uppercased(), color: .purple) }
            }
            if let o = m.originalTitle, o != m.title { Text(o).font(.subheadline).foregroundStyle(W.dim) }
            Text([m.releaseYear.map(String.init), m.runtimeLabel, m.directors.first].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(W.dim)
        }
    }

    private func statsRow(_ m: Movie) -> some View {
        HStack(spacing: 8) {
            if let a = m.avgUserRating { statBox(String(format: "%.1f", a), "TMDB", W.gold) }
        }
    }

    private func statBox(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.headline).foregroundStyle(c)
            Text(l).font(.subheadline.weight(.semibold)).foregroundStyle(W.dim)
        }
        .frame(minWidth: 58).card(radius: 10, padding: 8)
    }

    private func actionRow(_ m: Movie) -> some View {
        let saved = store.savedMovies.contains(m.id)
        let ranked = store.rankedIds.contains(m.id)
        return HStack(spacing: 8) {
            RatedButton(title: ranked ? "Ranked" : "Rank", style: ranked ? .tinted(W.green) : .accent, small: true) { store.startRank(m) }
                .accessibilityIdentifier("detail-rank")
            RatedButton(title: saved ? "Saved" : "Save", style: saved ? .tinted(W.blue) : .outline, small: true) { store.toggleSaved(m) }
                .accessibilityIdentifier("detail-save")
            RatedButton(title: "Review", style: .outline, small: true) { showReview = true }
                .accessibilityIdentifier("detail-review")
        }
    }

    private func castRow(_ m: Movie) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Cast")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(m.cast.prefix(8).enumerated()), id: \.offset) { _, c in
                        VStack(spacing: 4) {
                            Group {
                                if let p = c.profileURL, let u = URL(string: p) {
                                    AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { W.card }
                                } else { W.card }
                            }
                            .frame(width: 48, height: 48).background(Circle().fill(W.card)).clipShape(Circle())
                            Text(c.name.split(separator: " ").last.map(String.init) ?? c.name).font(.subheadline.weight(.semibold)).foregroundStyle(W.text).lineLimit(1)
                        }
                        .frame(width: 84)
                    }
                }
            }
        }
    }
}

/// New-review and edit-review sheet (ReviewModal.jsx).
struct ReviewSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let movie: Movie
    let existing: UserReview?
    @State private var rating = 0
    @State private var text = ""
    @State private var error: String?
    @State private var submitted = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView { content }
            .scrollDismissesKeyboard(.interactively)
            .background(W.bg)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            if submitted {
                VStack(spacing: 8) {
                    Text(existing == nil ? "Review Posted!" : "Review Updated").font(.headline).foregroundStyle(W.text)
                }
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical)
            } else {
                HStack {
                    Text(existing == nil ? "Write Review" : "Edit Review").font(.headline).foregroundStyle(W.text)
                    Spacer()
                    Button { dismiss() } label: { Text("Close").font(.subheadline).foregroundStyle(W.dim) }.hitArea()
                }
                HStack(spacing: 12) {
                    PosterView(url: movie.posterURL, title: movie.title, width: 40, height: 56, radius: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(movie.title).font(.headline).foregroundStyle(W.text)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        ForEach(1...10, id: \.self) { n in
                            Button { Haptics.light(); rating = n } label: {
                                Text("\(n)").font(.subheadline.weight(.semibold))
                                    .foregroundStyle(n <= rating ? .white : W.dim)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(n <= rating ? W.gold : W.card))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(n <= rating ? W.gold : W.border))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("rating-\(n)")
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    TextEditor(text: $text)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                        .font(.body).foregroundStyle(W.text)
                        .frame(minHeight: 120)
                        .card(radius: 12, padding: 8)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty { Text("What did you think? Be honest...").font(.body).foregroundStyle(W.dim).padding(16).allowsHitTesting(false) }
                        }
                        .onChange(of: text) { _, v in if v.count > 500 { text = String(v.prefix(500)) }; error = nil }
                        .accessibilityIdentifier("review-text")
                }
                if let e = error { Text(e).font(.subheadline).foregroundStyle(W.accent) }
                RatedButton(title: existing == nil ? "Post Review" : "Save Changes", style: rating > 0 && !text.trimmingCharacters(in: .whitespaces).isEmpty ? .accent : .outline, action: submit)
                    .opacity(rating > 0 && !text.trimmingCharacters(in: .whitespaces).isEmpty ? 1 : 0.5)
                    .accessibilityIdentifier("review-submit")
            }
        }
        .padding(20)
        .background(W.bg)
        .onAppear {
            if let e = existing { rating = e.rating; text = e.text }
        }
    }

    private func submit() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rating > 0, !t.isEmpty else { return }
        if Profanity.check(t) != nil { error = "Review contains inappropriate language. Please revise it."; return }
        if let e = existing {
            store.editReview(e, text: t, rating: rating)
            store.showToast("Review updated")
        } else {
            store.submitReview(movie: movie, rating: rating, text: t)
        }
        Haptics.success()
        withAnimation { submitted = true }
        Task { try? await Task.sleep(for: .seconds(1.1)); dismiss() }
    }
}
