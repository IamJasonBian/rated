import SwiftUI

/// Highlights carousel + Following/Everyone activity feed (HomeScreen.jsx).
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @State private var loaded = false
    @State private var loadError: String?
    @State private var tab = "following"
    @State private var apiFeed: [FeedItem]?
    @State private var highlights: [Movie] = []
    @State private var visible = 10

    private var feed: [FeedItem] {
        let base = tab == "following"
            ? store.userFeedItems + (apiFeed ?? Mock.followingFeed).filter { store.followingHandles.contains($0.user) }
            : store.userFeedItems + Mock.globalFeed
        return base.filter { !store.blockedUsers.contains($0.user) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                if !loaded {
                    skeleton
                } else {
                    if let e = loadError { errorBanner(e) }
                    SectionLabel(text: "HIGHLIGHTS")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(highlights) { m in highlightCard(m) }
                        }
                    }
                    .scrollClipDisabled()
                    SectionLabel(text: "ACTIVITY").padding(.top, 6)
                    UnderlineTabs(tabs: [("following", "Following"), ("everyone", "Everyone")], selection: $tab)
                    if tab == "following" && feed.isEmpty {
                        EmptyStateView(icon: "👥", title: "Nobody followed yet", subtitle: "Follow people to see their activity here")
                    }
                    // Plain VStack: the feed pages 10 at a time, and LazyVStack can loop
                    // re-measuring cards whose height changes (replies, like counts).
                    VStack(spacing: 10) {
                        ForEach(feed.prefix(visible)) { item in
                            FeedCard(item: item, showFollow: tab == "everyone", collapseReplies: tab == "everyone")
                        }
                    }
                    if feed.count > visible {
                        RatedButton(title: "Load \(min(10, feed.count - visible)) more", style: .outline, small: true) { visible += 10 }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(W.bg)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await load(); Catalog.shared.invalidate(); highlights = Array(await Catalog.shared.popular().prefix(6)) }
        .task {
            guard !loaded else { return }
            async let h = Catalog.shared.popular()
            await load()
            highlights = Array(await h.prefix(6))
            withAnimation { loaded = true }
        }
        .task(id: tab) { await store.loadReplies(for: feed.prefix(visible).map(\.id)) }
    }

    private func load() async {
        loadError = nil
        guard let uid = store.userId, let s = store.session else { return }
        if let rows = await APIClient.shared.feed(uid, token: s) {
            let mapped = rows.map { r -> FeedItem in
                let u = r.user?.username ?? r.user?.name ?? "user"
                return FeedItem(id: "api-\(r.movie.movie_id)-\(Int(r.ranked_at ?? 0))", type: .rating, user: "@\(u)",
                                avatar: String(u.prefix(1)).uppercased(), action: "rated", movieTitle: r.movie.title,
                                movieId: r.movie.movie_id, rating: r.score,
                                ts: Date(timeIntervalSince1970: r.ranked_at ?? 0))
            }
            // Backend rows first, then seeded friends' activity so the feed isn't sparse in dev.
            apiFeed = mapped + Mock.followingFeed
        } else if !(await APIClient.shared.ping()) {
            loadError = "Couldn't connect. Check your network and try again."
        }
    }

    private var header: some View {
        HStack {
            Text("RATED").mono(20, .black).tracking(-1).foregroundStyle(W.accent)
            Spacer()
            NavigationLink(value: Route.notifications) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill").font(.system(size: 16)).foregroundStyle(W.text)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(W.card)).overlay(Circle().stroke(W.border))
                    if store.unreadCount > 0 {
                        Text(store.unreadCount > 9 ? "9+" : "\(store.unreadCount)")
                            .mono(8, .black).foregroundStyle(.white)
                            .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                            .background(Capsule().fill(W.accent))
                            .offset(x: 4, y: -2)
                    }
                }
            }
            .accessibilityLabel("Notifications, \(store.unreadCount) unread")
            .accessibilityIdentifier("bell")
        }
        .padding(.top, 6)
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBlock(width: 90, height: 11)
            HStack(spacing: 10) { ForEach(0..<4, id: \.self) { _ in SkeletonBlock(width: 105, height: 148, radius: 12) } }
            ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 96, radius: 14) }
        }
    }

    private func errorBanner(_ e: String) -> some View {
        HStack(spacing: 10) {
            T("⚠️")
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't load your feed").mono(11, .bold).foregroundStyle(W.text)
                Text("\(e) · Showing cached content.").mono(9).foregroundStyle(W.dim)
            }
            Spacer()
            Button("Retry") { Task { loaded = false; await load(); loaded = true } }.mono(10, .bold)
        }
        .card(radius: 12, fill: W.orangeDim, stroke: W.orange.opacity(0.4), padding: 10)
    }

    private func highlightCard(_ m: Movie) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NavigationLink(value: Route.movie(m)) {
                PosterView(url: m.posterURL, title: m.title, width: 105, height: 148, radius: 12)
                    .overlay(alignment: .topLeading) {
                        if let r = m.trendingRank, r <= 3 {
                            Text("#\(r)").mono(9, .black).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(W.accent)).padding(6)
                        }
                    }
            }
            .accessibilityIdentifier("highlight-\(m.id)")
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.title).mono(10, .bold).foregroundStyle(W.text).lineLimit(1)
                    Text(m.releaseYear.map(String.init) ?? "").mono(8).foregroundStyle(W.dim)
                }
                Spacer(minLength: 2)
                Button { store.toggleSaved(m) } label: {
                    Text(store.savedMovies.contains(m.id) ? "◆" : "◇").mono(12).foregroundStyle(store.savedMovies.contains(m.id) ? W.blue : W.dim)
                }
                .accessibilityLabel(store.savedMovies.contains(m.id) ? "Unsave \(m.title)" : "Save \(m.title)")
            }
            .frame(width: 105)
        }
    }
}

struct FeedCard: View {
    @Environment(AppStore.self) private var store
    let item: FeedItem
    var showFollow = false
    var collapseReplies = false
    @State private var expanded = false
    @State private var replyOpen = false
    @State private var replyText = ""
    @FocusState private var replyFocused: Bool

    private var isOwn: Bool { item.user == "@you" || item.user == store.handle }
    private var movie: Movie? { item.movieId.flatMap { Catalog.shared.find($0, title: item.movieTitle) } }

    var body: some View {
        let replies = store.replies[item.id] ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                userLink { AvatarView(initial: item.avatar, size: 32) }
                VStack(alignment: .leading, spacing: 1) {
                    userLink { Text(item.user).mono(11, .bold).foregroundStyle(W.text) }
                    Text(TimeFmt.relative(item.ts)).mono(8).foregroundStyle(W.dim)
                }
                Spacer()
                if showFollow && !isOwn {
                    FollowPill(following: store.followingHandles.contains(item.user)) { store.toggleFollow(item.user) }
                }
                if let m = movie {
                    ShareLink(item: ShareLinks.movie(m), subject: Text(m.title), message: Text("Check out \(m.title) on RATED")) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 12)).foregroundStyle(W.dim)
                    }
                    .accessibilityLabel("Share \(m.title)")
                }
                ReportBlockMenu(targetType: "feed", targetId: item.id, targetLabel: "\(item.user) - \(item.movieTitle ?? item.action)", targetUser: isOwn ? nil : item.user)
            }
            content
            if !replies.isEmpty { replyThread(replies) }
            if replyOpen { replyInput }
            actions(replies.count)
        }
        .card(radius: 14, padding: 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed-\(item.id)")
    }

    @ViewBuilder
    private func userLink<L: View>(@ViewBuilder _ label: () -> L) -> some View {
        if isOwn { label() } else { NavigationLink(value: Route.user(item.user)) { label() }.buttonStyle(.plain) }
    }

    @ViewBuilder
    private var content: some View {
        let title = Text(item.movieTitle ?? "").foregroundStyle(W.accent).fontWeight(.bold)
        let rating = item.rating.map { Text("  ★ \($0.formatted(.number.precision(.fractionLength(0...1))))/10").foregroundStyle(W.gold) } ?? Text("")
        VStack(alignment: .leading, spacing: 4) {
            Group {
                switch item.type {
                case .rating, .review, .ranking:
                    movieLink { Text("\(T(item.action).foregroundStyle(W.dim)) \(title)\(rating)") }
                case .save:
                    movieLink { Text("\(Text("saved").foregroundStyle(W.dim)) \(title) \(T("to watch later 🎬").foregroundStyle(W.dim))") }
                case .streak:
                    T(item.action).foregroundStyle(W.text)
                }
            }
            .mono(11)
            if item.type == .review, let p = item.preview {
                Text("\"\(p.count > 90 ? String(p.prefix(90)) + "…" : p)\"").mono(10).italic().foregroundStyle(W.text.opacity(0.85))
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) { Rectangle().fill(W.border).frame(width: 2) }
            }
            if item.type == .ranking, let p = item.preview {
                movieLink { Text(p).mono(10, .semibold).foregroundStyle(W.blue) }
            }
        }
    }

    @ViewBuilder
    private func movieLink<L: View>(@ViewBuilder _ label: () -> L) -> some View {
        if let m = movie { NavigationLink(value: Route.movie(m)) { label() }.buttonStyle(.plain) } else { label() }
    }

    private func replyThread(_ replies: [Reply]) -> some View {
        let collapsed = collapseReplies && !expanded && replies.count > 1
        let shown = collapsed ? [replies.last!] : replies
        return VStack(alignment: .leading, spacing: 6) {
            if collapsed {
                Button("— View \(replies.count - 1) earlier \(replies.count - 1 == 1 ? "reply" : "replies")") { withAnimation { expanded = true } }
                    .mono(9, .semibold).foregroundStyle(W.dim)
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .top, spacing: 8) {
                    AvatarView(initial: r.avatar, size: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(r.user).mono(9, .bold).foregroundStyle(W.text)
                            Text(TimeFmt.relative(r.ts)).mono(8).foregroundStyle(W.dim)
                        }
                        Text(r.text).mono(10).foregroundStyle(W.text)
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(W.bg))
    }

    private var replyInput: some View {
        let valid = !replyText.trimmingCharacters(in: .whitespaces).isEmpty && replyText.count <= 280
        return VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 6) {
                TextField("Write a reply...", text: $replyText)
                    .focused($replyFocused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .onChange(of: replyText) { _, v in if v.count > 280 { replyText = String(v.prefix(280)) } }
                    .mono(11).foregroundStyle(W.text)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(W.bg))
                    .accessibilityIdentifier("reply-field")
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(Circle().fill(valid ? W.accent : W.border))
                }
                .disabled(!valid)
                .accessibilityLabel("Send reply")
            }
            if !replyText.isEmpty {
                Text("\(replyText.count) / 280").mono(8).foregroundStyle(replyText.count >= 252 ? W.accent : W.dim)
            }
        }
        .onAppear { replyFocused = true }
    }

    private func send() {
        store.postReply(item.id, text: replyText)
        replyText = ""
        replyOpen = false
        expanded = true
    }

    private func actions(_ replyCount: Int) -> some View {
        let liked = store.isLiked(item)
        return HStack(spacing: 16) {
            Button { store.toggleLike(item) } label: {
                HStack(spacing: 4) {
                    Image(systemName: liked ? "heart.fill" : "heart").foregroundStyle(liked ? W.accent : W.dim)
                        .symbolEffect(.bounce, value: liked)
                    Text("\(store.likeCount(item))").mono(10).foregroundStyle(W.dim).contentTransition(.numericText())
                }
            }
            .accessibilityLabel("\(liked ? "Unlike" : "Like") post, \(store.likeCount(item)) likes")
            .accessibilityIdentifier("like-\(item.id)")
            Button {
                Haptics.light()
                if collapseReplies && replyCount > 1 && !expanded { withAnimation { expanded = true } }
                else { withAnimation { replyOpen.toggle() }; replyText = "" }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left").foregroundStyle(W.dim)
                    Text(replyCount > 0 ? "\(replyCount)" : "Reply").mono(10).foregroundStyle(W.dim)
                }
            }
            .accessibilityIdentifier("reply-\(item.id)")
            if let m = movie {
                Button { store.startRank(m) } label: {
                    HStack(spacing: 4) { T("⚡"); Text("Rank").mono(10).foregroundStyle(W.dim) }
                }
                Button { store.toggleSaved(m) } label: {
                    let saved = store.savedMovies.contains(m.id)
                    HStack(spacing: 4) {
                        Text(saved ? "◆" : "◇").foregroundStyle(saved ? W.blue : W.dim)
                        Text(saved ? "Saved" : "Save").mono(10).foregroundStyle(saved ? W.blue : W.dim)
                    }
                }
            }
            Spacer()
        }
        .font(.system(size: 13))
        .buttonStyle(.plain)
    }
}
