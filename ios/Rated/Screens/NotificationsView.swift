import SwiftUI

/// Activity notifications with follow-request approval (NotificationsScreen.jsx).
struct NotificationsView: View {
    @Environment(AppStore.self) private var store
    @State private var items: [AppNotification] = Mock.notifications
    @State private var tab = "all"
    @State private var declining: AppNotification?

    private func visible(_ n: AppNotification) -> Bool { n.user.map { !store.blockedUsers.contains($0) } ?? true }
    private var pending: [AppNotification] { items.filter { $0.kind == .followRequest && visible($0) } }
    private var filtered: [AppNotification] {
        items.filter { n in
            switch tab {
            case "followers": n.kind != .watchlist
            case "watchlist": n.kind == .watchlist
            default: true
            }
        }
        .filter(visible)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if store.isPrivate && !pending.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            T("⏳")
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Follow Requests").mono(12, .bold).foregroundStyle(W.text)
                                Text("\(pending.count) people waiting for approval").mono(9).foregroundStyle(W.dim)
                            }
                        }
                        ForEach(pending) { requestRow($0) }
                    }
                    .card(radius: 14, fill: W.purpleDim, stroke: W.purple.opacity(0.3), padding: 12)
                }
                UnderlineTabs(tabs: [("all", "All"), ("followers", "Followers"), ("watchlist", "Watchlist")], selection: $tab)
                if tab == "followers" && !pending.isEmpty && !store.isPrivate {
                    SectionLabel(text: "⏳ PENDING REQUESTS · \(pending.count)")
                    ForEach(pending) { requestRow($0) }
                }
                if filtered.isEmpty { EmptyStateView(icon: "🔔", title: "All caught up", subtitle: "No notifications in this category") }
                ForEach(filtered) { n in row(n) }
            }
            .padding(.horizontal, 18).padding(.vertical, 8)
        }
        .background(W.bg)
        .navigationTitle("NOTIFICATIONS")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await fetch() }
        .task {
            await fetch()
            if let uid = store.userId { await APIClient.shared.markAllNotificationsRead(uid) }
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation { for i in items.indices { items[i].read = true } }
            store.unreadCount = 0
        }
        .alert("Decline follow request?", isPresented: Binding(get: { declining != nil }, set: { if !$0 { declining = nil } }), presenting: declining) { n in
            Button("Cancel", role: .cancel) {}
            Button("Decline", role: .destructive) {
                items.removeAll { $0.id == n.id }
                if let uid = store.userId { Task { await APIClient.shared.deleteNotification(uid, id: n.id) } }
            }
        } message: { n in Text("\(n.user ?? "This person") won't be notified, but they can send another request.") }
    }

    private func fetch() async {
        guard let uid = store.userId, let rows = await APIClient.shared.notifications(uid), !rows.isEmpty else { return }
        // Backend rows on top of the seeded examples so dev builds still demo every type.
        let mapped = rows.map { r -> AppNotification in
            let u = r.actor?.username ?? r.actor?.name ?? "?"
            let kind: NotificationKind = r.type == "follow_request" ? .followRequest : .follow
            let fallback = ["follow": "started following you", "follow_request": "requested to follow you", "review": "wrote a review", "rank": "ranked a movie"][r.type] ?? ""
            return AppNotification(id: r.id, kind: kind, read: r.read, ts: r.created_at.map { Date(timeIntervalSince1970: $0) } ?? .now,
                                   user: r.actor?.username.map { "@\($0)" }, avatar: String(u.prefix(1)).uppercased(), text: r.body ?? fallback)
        }
        items = mapped + Mock.notifications
    }

    private func approve(_ n: AppNotification) {
        Haptics.success()
        if let i = items.firstIndex(where: { $0.id == n.id }) {
            items[i].kind = .follow
            items[i].read = true
            items[i].text = "is now following you"
        }
        if let u = n.user { store.approveFollower(u) }
    }

    private func requestRow(_ n: AppNotification) -> some View {
        HStack(spacing: 10) {
            AvatarView(initial: n.avatar ?? "?", size: 28)
            Text(n.user ?? "").mono(11, .bold).foregroundStyle(W.text)
            Spacer()
            Button { approve(n) } label: { Image(systemName: "checkmark").foregroundStyle(.white).frame(width: 30, height: 30).background(Circle().fill(W.green)) }
                .accessibilityLabel("Approve follow request from \(n.user ?? "")")
            Button { declining = n } label: { Image(systemName: "xmark").foregroundStyle(W.dim).frame(width: 30, height: 30).background(Circle().stroke(W.border)) }
                .accessibilityLabel("Decline follow request from \(n.user ?? "")")
        }
        .buttonStyle(.plain)
    }

    private func row(_ n: AppNotification) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let a = n.avatar, let u = n.user {
                NavigationLink(value: Route.user(u)) {
                    AvatarView(initial: a, size: 36)
                        .overlay(alignment: .bottomTrailing) {
                            Text(n.kind == .follow ? "👤" : "⏳").font(.system(size: 9)).padding(2).background(Circle().fill(W.card))
                        }
                }
                .buttonStyle(.plain)
            } else {
                T(n.icon ?? "🔔").font(.system(size: 18)).frame(width: 36, height: 36).background(Circle().fill(W.card))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Text(n.user ?? n.movie ?? "").bold().foregroundStyle(n.movie != nil ? W.accent : W.text)) \(Text(n.text).foregroundStyle(W.text.opacity(0.85)))")
                    .mono(11)
                Text(TimeFmt.relative(n.ts)).mono(8).foregroundStyle(W.dim)
                if n.kind == .followRequest && store.isPrivate {
                    HStack(spacing: 6) {
                        RatedButton(title: "✓ Approve", style: .tinted(W.green), small: true) { approve(n) }
                        RatedButton(title: "✕ Decline", style: .outline, small: true) { declining = n }
                    }
                    .frame(maxWidth: 220)
                }
                if n.kind == .follow, let u = n.user {
                    let f = store.followingHandles.contains(u)
                    Button(f ? "✓ Following" : "+ Follow Back") { store.toggleFollow(u) }
                        .mono(9, .bold).foregroundStyle(f ? W.dim : W.accent)
                        .buttonStyle(.plain)
                }
            }
            Spacer()
            if !n.read { Circle().fill(W.accent).frame(width: 8, height: 8).padding(.top, 4).accessibilityLabel("Unread") }
        }
        .card(radius: 12, fill: n.read ? W.card : W.accent.opacity(0.05), padding: 10)
        .onTapGesture {
            if let i = items.firstIndex(where: { $0.id == n.id }) { items[i].read = true }
            if let uid = store.userId { Task { await APIClient.shared.markNotificationRead(uid, id: n.id) } }
            if n.kind == .followRequest { tab = "followers" }
        }
    }
}
