import SwiftUI

/// Movie / upcoming detail (MovieDetailScreen.jsx): backdrop, trailer, stats,
/// rank/save/review actions, cast, followed users' takes, and the affiliate
/// ticket CTA when the backend says the user and someone they follow both rated it.
struct MovieDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    let movie: Movie
    @State private var m: Movie?
    @State private var showReview = false
    @State private var trailerURL: IdentifiableURL?
    @State private var viewerURL: IdentifiableURL?
    @State private var tickets: APITickets?
    @State private var synopsisExpanded = false

    var body: some View {
        let m = self.m ?? movie
        let upcoming = m.isUpcoming
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(m)
                VStack(alignment: .leading, spacing: 14) {
                    titleBlock(m, upcoming: upcoming)
                    if !upcoming { statsRow(m) }
                    if upcoming, let a = m.anticipationScore { anticipation(m, score: a) }
                    if !m.genres.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(m.genres, id: \.self) { g in
                                    Text(g).mono(9, .semibold).foregroundStyle(W.dim)
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(Capsule().fill(W.card)).overlay(Capsule().stroke(W.border))
                                }
                            }
                        }
                    }
                    if !m.synopsis.isEmpty {
                        Text(m.synopsis).mono(11).foregroundStyle(W.text.opacity(0.85)).lineSpacing(3)
                            .lineLimit(synopsisExpanded ? nil : 4)
                            .onTapGesture { withAnimation { synopsisExpanded.toggle() } }
                    }
                    if let t = tickets, t.show { ticketCTA(t) }
                    actionRow(m, upcoming: upcoming)
                    if let first = m.cast.first, first.name != "TBA" { castRow(m) }
                    if !upcoming { communityStats(m) }
                    if !upcoming { followedTakes(m) }
                    if !m.keywords.isEmpty {
                        Text(m.keywords.prefix(6).map { "#\($0)" }.joined(separator: "  ")).mono(9).foregroundStyle(W.dim)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 30)
            }
        }
        .background(W.bg)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: ShareLinks.movie(m), subject: Text(m.title), message: Text("Check out \(m.title) on RATED")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share \(m.title)")
            }
        }
        .sheet(isPresented: $showReview) { ReviewSheet(movie: m, existing: nil).presentationDetents([.large]) }
        .sheet(item: $trailerURL) { SafariView(url: $0.url).ignoresSafeArea() }
        .fullScreenCover(item: $viewerURL) { ImageViewer(url: $0.url) }
        .task(id: movie.id) {
            self.m = await Catalog.shared.detail(movie)
            if let uid = store.userId { tickets = await APIClient.shared.tickets(uid, movieId: movie.id, token: store.session) }
        }
        .onChange(of: store.rankedIds) {
            // Ranking may unlock the ticket CTA — re-check.
            Task { if let uid = store.userId { tickets = await APIClient.shared.tickets(uid, movieId: movie.id, token: store.session) } }
        }
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
            .frame(height: 260).frame(maxWidth: .infinity).clipped()
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
                            Image(systemName: "play.fill")
                            Text("PLAY TRAILER").mono(9, .black)
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

    private func titleBlock(_ m: Movie, upcoming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(m.title).mono(19, .black).foregroundStyle(W.text)
                    .accessibilityIdentifier("detail-title")
                if m.isInternational, let l = m.originalLanguage { BadgeView(text: l.uppercased(), color: .purple) }
                if upcoming { BadgeView(text: "UPCOMING", color: .orange) }
            }
            if let o = m.originalTitle, o != m.title { Text(o).mono(10).foregroundStyle(W.dim) }
            Text([m.releaseYear.map(String.init), m.runtimeLabel, m.contentRating, m.directors.first].compactMap { $0 }.joined(separator: " · "))
                .mono(10).foregroundStyle(W.dim)
            if upcoming, m.releaseDate != nil {
                T("📅 \(TimeFmt.releaseDate(m.releaseDate)) · \(TimeFmt.countdown(m.releaseDate))").mono(10, .bold).foregroundStyle(W.orange)
            }
            if upcoming, let r = m.mustSeeReason { Text(r).mono(10).foregroundStyle(W.gold) }
        }
    }

    private func statsRow(_ m: Movie) -> some View {
        HStack(spacing: 8) {
            if let r = m.globalRank { statBox("#\(r)", "RATED", W.accent) }
            if let i = m.imdbRating { statBox(String(format: "%.1f", i), "IMDb", W.gold) }
            if let rt = m.rottenTomatoes { statBox("\(rt)%", "RT", W.green) }
            if let e = m.globalElo { statBox("\(e)", "ELO", W.blue) }
            if m.imdbRating == nil, let a = m.avgUserRating { statBox(String(format: "%.1f", a), "TMDB", W.gold) }
        }
    }

    private func statBox(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).mono(14, .black).foregroundStyle(c)
            Text(l).mono(7, .bold).foregroundStyle(W.dim)
        }
        .frame(minWidth: 58).card(radius: 10, padding: 8)
    }

    private func anticipation(_ m: Movie, score: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ANTICIPATION").mono(9, .bold).foregroundStyle(W.dim)
                Spacer()
                Text("\(score)/1000").mono(10, .black).foregroundStyle(W.orange)
            }
            ProgressView(value: Double(score) / 1000).tint(W.orange)
            T("👀 \(m.watchlistCount.formatted()) watching").mono(9).foregroundStyle(W.dim)
        }
        .card(radius: 12, padding: 12)
    }

    private func ticketCTA(_ t: APITickets) -> some View {
        let raters = (t.co_raters ?? []).compactMap { $0.username.map { "@\($0)" } }
        let who = raters.isEmpty ? "someone you follow" : raters.count == 1 ? raters[0] : "\(raters[0]) +\(raters.count - 1)"
        return Button {
            Haptics.medium()
            if let s = t.url, let u = URL(string: s) { openURL(u) }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    T("🎟 \((t.label ?? "Buy tickets").uppercased())").mono(12, .black).foregroundStyle(.white)
                    Text("You and \(who) both rated this").mono(9).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(.white)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [W.accent, W.orange], startPoint: .leading, endPoint: .trailing)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("buy-tickets")
    }

    @ViewBuilder
    private func actionRow(_ m: Movie, upcoming: Bool) -> some View {
        if upcoming {
            let inWL = store.watchlist.contains(m.id)
            RatedButton(title: inWL ? "◆ IN WATCHLIST" : "+ ADD TO WATCHLIST", style: inWL ? .tinted(W.blue) : .accent) { store.toggleWatchlist(m.id) }
                .accessibilityIdentifier("detail-watchlist")
        } else {
            let saved = store.savedMovies.contains(m.id)
            let ranked = store.rankedIds.contains(m.id)
            HStack(spacing: 8) {
                RatedButton(title: ranked ? "✓ RANKED" : "⚡ RANK", style: ranked ? .tinted(W.green) : .accent, small: true) {
                    if ranked { store.reRank(m) } else { store.startRank(m) }
                }
                .accessibilityIdentifier("detail-rank")
                RatedButton(title: saved ? "◆ SAVED" : "◇ SAVE", style: saved ? .tinted(W.blue) : .outline, small: true) { store.toggleSaved(m) }
                    .accessibilityIdentifier("detail-save")
                RatedButton(title: "✎ REVIEW", style: .outline, small: true) { showReview = true }
                    .accessibilityIdentifier("detail-review")
            }
        }
    }

    private func castRow(_ m: Movie) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "CAST")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(m.cast.prefix(8).enumerated()), id: \.offset) { _, c in
                        VStack(spacing: 4) {
                            Group {
                                if let p = c.profileURL, let u = URL(string: p) {
                                    AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { T("👤") }
                                } else { T("👤").font(.system(size: 20)) }
                            }
                            .frame(width: 48, height: 48).background(Circle().fill(W.card)).clipShape(Circle())
                            Text(c.name.split(separator: " ").last.map(String.init) ?? c.name).mono(9, .bold).foregroundStyle(W.text).lineLimit(1)
                            Text(c.character ?? "").mono(8).foregroundStyle(W.dim).lineLimit(1)
                        }
                        .frame(width: 64)
                    }
                }
            }
        }
    }

    private func communityStats(_ m: Movie) -> some View {
        HStack {
            ForEach([(m.userRatingCount, "Ratings"), (m.reviewCount, "Reviews"), (m.watchlistCount, "Watchlisted"), (m.seenCount, "Seen")], id: \.1) { n, l in
                VStack(spacing: 2) {
                    Text(TimeFmt.compact(n)).mono(13, .black).foregroundStyle(W.text)
                    Text(l).mono(8).foregroundStyle(W.dim)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .card(radius: 12, padding: 10)
    }

    /// Followed users' scores, synthesised from a stable (handle + movie) hash
    /// exactly like the web so the same people show up consistently.
    @ViewBuilder
    private func followedTakes(_ m: Movie) -> some View {
        let bits = ["A masterclass in tension and pacing.", "Exactly the kind of film I come back to.",
                    "Beautifully shot, emotionally wrecking.", "Overrated but still compelling.",
                    "Genre-defining performance from the lead.", "Visually stunning but narratively uneven."]
        let takes: [(String, UserProfile, Int, String?)] = store.followingHandles.sorted().compactMap { h in
            guard let p = Mock.profiles[h] else { return nil }
            let seed = charSum(h + m.id)
            guard seed % 3 != 0 else { return nil }
            return (h, p, 6 + seed % 5, seed % 4 == 0 ? bits[seed % bits.count] : nil)
        }
        if !takes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    T("👥 PEOPLE YOU FOLLOW").mono(9, .bold).foregroundStyle(W.dim)
                    Text("· \(takes.count)").mono(9).foregroundStyle(W.dim)
                }
                ForEach(takes, id: \.0) { h, p, score, review in
                    NavigationLink(value: Route.user(h)) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                AvatarView(initial: p.avatar, size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) { Text(h).mono(11, .bold).foregroundStyle(W.text); T(p.badge) }
                                    Text(review == nil ? "ranked" : "reviewed").mono(8).foregroundStyle(W.dim)
                                }
                                Spacer()
                                Text("\(score)/10").mono(13, .black).foregroundStyle(W.gold)
                            }
                            if let r = review { Text("\"\(r)\"").mono(10).italic().foregroundStyle(W.text.opacity(0.85)) }
                        }
                        .card(radius: 12, padding: 10)
                    }
                    .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 16) {
            if submitted {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(W.green)
                        .symbolEffect(.bounce, value: submitted)
                    Text(existing == nil ? "Review Posted!" : "Review Updated").mono(14, .black).foregroundStyle(W.text)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("✎ \(existing == nil ? "WRITE REVIEW" : "EDIT REVIEW")").mono(13, .heavy).foregroundStyle(W.text)
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(W.dim) }.accessibilityLabel("Close")
                }
                HStack(spacing: 12) {
                    PosterView(url: movie.posterURL, title: movie.title, width: 40, height: 56, radius: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(movie.title).mono(13, .heavy).foregroundStyle(W.text)
                        Text([movie.releaseYear.map(String.init), movie.directors.first].compactMap { $0 }.joined(separator: " · ")).mono(9).foregroundStyle(W.dim)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "YOUR RATING")
                    HStack(spacing: 4) {
                        ForEach(1...10, id: \.self) { n in
                            Button { Haptics.light(); rating = n } label: {
                                Text("\(n)").mono(11, .black)
                                    .foregroundStyle(n <= rating ? .white : W.dim)
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(n <= rating ? W.gold : W.card))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(n <= rating ? W.gold : W.border))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("rating-\(n)")
                        }
                    }
                    if rating > 0 { Text("★ \(rating)/10").mono(11, .bold).foregroundStyle(W.gold) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SectionLabel(text: "YOUR REVIEW")
                        Text("\(text.count) / 500").mono(9).foregroundStyle(text.count > 450 ? W.accent : W.dim)
                    }
                    TextEditor(text: $text)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                        .mono(12).foregroundStyle(W.text)
                        .frame(minHeight: 120)
                        .card(radius: 12, padding: 8)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty { Text("What did you think? Be honest...").mono(12).foregroundStyle(W.dim).padding(16).allowsHitTesting(false) }
                        }
                        .onChange(of: text) { _, v in if v.count > 500 { text = String(v.prefix(500)) }; error = nil }
                        .accessibilityIdentifier("review-text")
                }
                if let e = error { Text("✗ \(e)").mono(10).foregroundStyle(W.accent) }
                RatedButton(title: existing == nil ? "POST REVIEW" : "SAVE CHANGES", style: rating > 0 && !text.trimmingCharacters(in: .whitespaces).isEmpty ? .accent : .outline, action: submit)
                    .accessibilityIdentifier("review-submit")
                Spacer()
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
