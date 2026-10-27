import Contacts
import CryptoKit
import PhotosUI
import SwiftUI
import UserNotifications

enum SettingsSection: String, CaseIterable, Hashable, Identifiable {
    case account, privacy, findFriends, notifications, appearance, about
    var id: String { rawValue }

    var icon: String { ["👤", "🔒", "👥", "🔔", "🎨", "ℹ️"][Self.allCases.firstIndex(of: self)!] }
    var label: String { ["Account", "Privacy", "Find Friends", "Notifications", "Appearance", "About"][Self.allCases.firstIndex(of: self)!] }
    var sub: String {
        ["Username, connected accounts", "Account visibility, follow requests", "Sync contacts, invite friends",
         "Push, email, activity alerts", "Theme, text size", "Version, Terms, Privacy, developer"][Self.allCases.firstIndex(of: self)!]
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    let initial: SettingsSection?
    @State private var pushed = false

    var body: some View {
        List {
            Section {
                ForEach(SettingsSection.allCases) { s in
                    NavigationLink {
                        SettingsDetail(section: s)
                    } label: {
                        HStack(spacing: 12) {
                            T(s.icon).font(.system(size: 18))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(s.label).mono(12, .bold).foregroundStyle(W.text)
                                    if s == .privacy && store.isPrivate { BadgeView(text: "PRIVATE", color: .purple) }
                                }
                                Text(s.sub).mono(9).foregroundStyle(W.dim)
                            }
                        }
                    }
                    .accessibilityIdentifier("settings-\(s.rawValue)")
                }
            }
            .listRowBackground(W.card)
            Section {
                Button(role: .destructive) { store.signOut() } label: {
                    Text("Sign Out").mono(12, .bold).frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("sign-out")
            } footer: {
                Text("RATED v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                    .mono(9).foregroundStyle(W.dim).frame(maxWidth: .infinity).padding(.top, 8)
            }
            .listRowBackground(W.card)
        }
        .scrollContentBackground(.hidden)
        .background(W.bg)
        .navigationTitle("SETTINGS")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $pushed) { if let s = initial { SettingsDetail(section: s) } }
        .onAppear { if initial != nil && !pushed { pushed = true } }
    }
}

struct SettingsDetail: View {
    let section: SettingsSection

    var body: some View {
        Group {
            switch section {
            case .account: AccountSettings()
            case .privacy: PrivacySettings()
            case .findFriends: FindFriendsSettings()
            case .notifications: NotificationSettingsView()
            case .appearance: AppearanceSettings()
            case .about: AboutSettings()
            }
        }
        .scrollContentBackground(.hidden)
        .background(W.bg)
        .navigationTitle(section.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Account

private struct AccountSettings: View {
    @Environment(AppStore.self) private var store
    @State private var name = ""
    @State private var bio = ""
    @State private var newUsername = ""
    @State private var status: String?
    @State private var saved = false
    @State private var profileError: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var cropImage: IdentifiableImage?
    @State private var deleteStep = 0
    @State private var deleteText = ""

    private var daysLeft: Int {
        guard let last = store.lastUsernameChange else { return 0 }
        return max(0, Int(ceil((last.addingTimeInterval(Moderation.usernameCooldown).timeIntervalSinceNow) / 86400)))
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        AvatarView(initial: store.avatarInitial, size: 64, image: store.profilePic)
                            .overlay(alignment: .bottomTrailing) { Image(systemName: "camera.circle.fill").font(.system(size: 20)).foregroundStyle(W.accent) }
                    }
                    .accessibilityLabel("Change profile photo")
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text("DISPLAY NAME").mono(9, .bold).foregroundStyle(W.dim); Spacer(); Text("\(name.count)/30").mono(8).foregroundStyle(W.dim) }
                        TextField("Your full name", text: $name).mono(13)
                            .onChange(of: name) { _, v in if v.count > 30 { name = String(v.prefix(30)) } }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("BIO").mono(9, .bold).foregroundStyle(W.dim); Spacer(); Text("\(bio.count)/130").mono(8).foregroundStyle(W.dim) }
                    TextField("Tell people about your taste in film...", text: $bio, axis: .vertical).mono(12).lineLimit(2...4)
                        .onChange(of: bio) { _, v in if v.count > 130 { bio = String(v.prefix(130)) } }
                }
                if let e = profileError { Text("✗ \(e)").mono(10).foregroundStyle(W.accent) }
                Button(saved ? "✓ SAVED" : "SAVE PROFILE") { saveProfile() }.mono(11, .black).foregroundStyle(saved ? W.green : W.accent)
                    .accessibilityIdentifier("save-profile")
            } header: { Text("EDIT PROFILE").mono(9, .bold) }
            .listRowBackground(W.card)

            Section {
                HStack(spacing: 4) {
                    Text("@").foregroundStyle(W.dim)
                    TextField("username", text: $newUsername).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(daysLeft > 0)
                        .onChange(of: newUsername) { _, v in check(v) }
                    Text(statusLabel).mono(9, .bold).foregroundStyle(status == "available" ? W.green : W.dim)
                }
                .mono(13)
                Button("SAVE USERNAME") {
                    Task { if await store.changeUsername(newUsername) { status = "updated"; Haptics.success() } }
                }
                .mono(11, .black).disabled(status != "available" || daysLeft > 0)
            } header: { Text("CHANGE USERNAME").mono(9, .bold) } footer: {
                T("🔒 Username can be changed once every 30 days.\(daysLeft > 0 ? " You can change it again in \(daysLeft) \(daysLeft == 1 ? "day" : "days")." : "")").mono(9)
            }
            .listRowBackground(W.card)

            Section {
                HStack(spacing: 10) {
                    Image(systemName: store.provider == .apple ? "applelogo" : "g.circle.fill").frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.email ?? (store.provider == .apple ? "user@icloud.com" : "user@gmail.com")).mono(11, .bold)
                        Text("Connected via \(store.provider == .apple ? "Apple" : "Google")").mono(9).foregroundStyle(W.dim)
                    }
                    Spacer()
                    Image(systemName: "checkmark").foregroundStyle(W.green)
                }
            } header: { Text("CONNECTED ACCOUNT").mono(9, .bold) }
            .listRowBackground(W.card)

            Section {
                Button(role: .destructive) { deleteText = ""; deleteStep = 1 } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        T("⚠️ Delete Account").mono(12, .bold)
                        Text("Permanently erase your account and all data").mono(9).foregroundStyle(W.dim)
                    }
                }
            }
            .listRowBackground(W.card)
        }
        .onAppear { name = store.displayName; bio = store.bio; newUsername = store.username }
        .onChange(of: photoItem) { _, item in
            Task {
                if let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) { cropImage = IdentifiableImage(image: img) }
                photoItem = nil
            }
        }
        .fullScreenCover(item: $cropImage) { img in
            CropperView(image: img.image) { jpeg in
                store.updateProfilePic(jpeg)
                store.showToast("Photo updated")
            }
        }
        .alert("Delete Account?", isPresented: Binding(get: { deleteStep == 1 }, set: { if !$0 && deleteStep == 1 { deleteStep = 0 } })) {
            Button("Keep Account", role: .cancel) { deleteStep = 0 }
            Button("Continue", role: .destructive) { Task { try? await Task.sleep(for: .milliseconds(350)); deleteStep = 2 } }
        } message: {
            Text("This will permanently erase your rankings and reviews, remove your profile and username, delete your watchlist and saved films, and remove you from your followers' feeds. This cannot be undone.")
        }
        .alert("Final Confirmation", isPresented: Binding(get: { deleteStep == 2 }, set: { if !$0 { deleteStep = 0 } })) {
            TextField("Type DELETE to confirm", text: $deleteText)
            Button("Cancel", role: .cancel) { deleteStep = 0 }
            Button("Delete Forever", role: .destructive) {
                if deleteText == "DELETE" { Task { await store.deleteAccount() } } else { store.showToast("Type DELETE exactly to confirm", .error) }
            }
        } message: { Text("To confirm, type DELETE below. Your username becomes available to others after 30 days.") }
    }

    private var statusLabel: String {
        if daysLeft > 0 { return "🔒 \(daysLeft)d left" }
        return ["available": "available ✓", "taken": "taken", "invalid": "too short", "profane": "blocked", "checking": "…", "updated": "updated ✓"][status ?? ""] ?? ""
    }

    private func saveProfile() {
        if Profanity.check(name) != nil { profileError = "Display name contains inappropriate language. Please revise it."; return }
        if Profanity.check(bio) != nil { profileError = "Bio contains inappropriate language. Please revise it."; return }
        profileError = nil
        store.updateProfile(name: name.trimmingCharacters(in: .whitespaces), bio: bio.trimmingCharacters(in: .whitespaces))
        Haptics.success()
        saved = true
        Task { try? await Task.sleep(for: .seconds(2)); saved = false }
    }

    private func check(_ raw: String) {
        let clean = String(Usernames.sanitize(raw).prefix(20))
        if clean != raw { newUsername = clean; return }
        if clean == store.username { status = nil; return }
        if clean.count < 4 { status = "invalid"; return }
        if Profanity.check(clean) != nil { status = "profane"; return }
        status = "checking"
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard newUsername == clean else { return }
            let ok = await APIClient.shared.checkUsername(clean) ?? !Usernames.taken.contains(clean)
            if newUsername == clean { status = ok ? "available" : "taken" }
        }
    }
}

struct IdentifiableImage: Identifiable { let image: UIImage; let id = UUID() }

/// Circular drag/pinch cropper that renders a 256×256 JPEG (components/CropperModal.jsx).
struct CropperView: View {
    let image: UIImage
    var onSave: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    private let frame: CGFloat = 280

    var body: some View {
        VStack(spacing: 24) {
            Text("Move and Scale").mono(13, .bold).foregroundStyle(.white)
            cropped(scale: scale * pinch, offset: CGSize(width: offset.width + drag.width, height: offset.height + drag.height))
                .frame(width: frame, height: frame)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 2))
                .contentShape(Circle())
                .gesture(DragGesture().updating($drag) { v, s, _ in s = v.translation }
                    .onEnded { v in offset.width += v.translation.width; offset.height += v.translation.height })
                .simultaneousGesture(MagnifyGesture().updating($pinch) { v, s, _ in s = v.magnification }
                    .onEnded { v in scale = max(1, min(5, scale * v.magnification)) })
            HStack(spacing: 12) {
                RatedButton(title: "Cancel", style: .outline) { dismiss() }
                RatedButton(title: "Use Photo") {
                    let r = ImageRenderer(content: cropped(scale: scale, offset: offset).frame(width: frame, height: frame).clipped())
                    r.scale = 256 / frame
                    if let ui = r.uiImage, let jpeg = ui.jpegData(compressionQuality: 0.85) { onSave(jpeg) }
                    dismiss()
                }
            }
            .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }

    private func cropped(scale: CGFloat, offset: CGSize) -> some View {
        Image(uiImage: image).resizable().scaledToFill()
            .frame(width: frame, height: frame)
            .scaleEffect(scale)
            .offset(offset)
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    @Environment(AppStore.self) private var store
    @State private var showBlocked = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { store.isPrivate }, set: { Haptics.light(); store.setPrivate($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Private Account").mono(12, .bold)
                        Text("Only approved followers can see your rankings, reviews, and activity.").mono(9).foregroundStyle(W.dim)
                    }
                }
                .tint(W.purple)
                .accessibilityIdentifier("private-toggle")
                if store.isPrivate {
                    VStack(alignment: .leading, spacing: 2) {
                        T("🔒 Private Mode Active").mono(11, .bold).foregroundStyle(W.purple)
                        Text("New followers need your approval before they can see your content. Existing approved followers are unaffected.").mono(9).foregroundStyle(W.dim)
                    }
                }
            } footer: { Text("Switching to private won't remove existing followers. To remove a follower, go to your Followers list.").mono(9) }
            .listRowBackground(W.card)
            Section {
                Button { showBlocked = true } label: {
                    HStack {
                        T("🚫")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Blocked Users").mono(12, .bold).foregroundStyle(W.text)
                            Text(store.blockedUsers.isEmpty ? "You haven't blocked anyone" : "\(store.blockedUsers.count) blocked").mono(9).foregroundStyle(W.dim)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(W.dim)
                    }
                }
            }
            .listRowBackground(W.card)
        }
        .sheet(isPresented: $showBlocked) {
            NavigationStack {
                List {
                    Section {
                        if store.blockedUsers.isEmpty {
                            EmptyStateView(icon: "🌿", title: "Nobody blocked", subtitle: "You haven't blocked anyone yet.")
                        }
                        ForEach(store.blockedUsers.sorted(), id: \.self) { h in
                            let p = Mock.profiles[h] ?? .placeholder(for: h)
                            HStack(spacing: 10) {
                                AvatarView(initial: p.avatar, size: 32)
                                VStack(alignment: .leading) {
                                    Text(h).mono(12, .bold)
                                    if !p.bio.isEmpty { Text(p.bio).mono(9).foregroundStyle(W.dim) }
                                }
                                Spacer()
                                Button("Unblock") { store.unblock(h) }.mono(10, .bold).buttonStyle(.bordered)
                            }
                        }
                    } footer: { Text("People you've blocked can't see your profile, posts, or reviews. They also can't follow you or send you notifications.").mono(9) }
                    .listRowBackground(W.card)
                }
                .scrollContentBackground(.hidden).background(W.bg)
                .navigationTitle("Blocked Users · \(store.blockedUsers.count)").navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Find friends

/// On-device contact hashing: emails/phones are normalised and SHA-256 hashed
/// so only digests would ever leave the device for matching.
enum ContactMatcher {
    static func hashedIdentifiers() async throws -> [String] {
        let store = CNContactStore()
        guard try await store.requestAccess(for: .contacts) else { return [] }
        return try await Task.detached {
            var hashes: Set<String> = []
            let req = CNContactFetchRequest(keysToFetch: [CNContactEmailAddressesKey as CNKeyDescriptor, CNContactPhoneNumbersKey as CNKeyDescriptor])
            try store.enumerateContacts(with: req) { c, _ in
                let ids = c.emailAddresses.map { ($0.value as String).lowercased().trimmingCharacters(in: .whitespaces) }
                    + c.phoneNumbers.map { $0.value.stringValue.filter(\.isNumber) }
                for id in ids where !id.isEmpty {
                    hashes.insert(SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined())
                }
            }
            return Array(hashes)
        }.value
    }
}

struct FindFriendsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            T("👋 FIND FRIENDS").mono(14, .black).foregroundStyle(W.text)
            Text("See which of your friends are already on RATED, or invite them to join.").mono(10).foregroundStyle(W.dim)
            FindFriendsActions()
            Text("We never post or message on your behalf. Contact data stays private and is only used to find matches.").mono(9).foregroundStyle(W.dim)
            RatedButton(title: "Close", style: .outline) { dismiss() }
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(W.bg)
    }
}

private struct FindFriendsActions: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var syncing = false

    var body: some View {
        let url = ShareLinks.invite(store.username)
        VStack(spacing: 8) {
            Button {
                Haptics.light()
                syncing = true
                Task {
                    defer { syncing = false }
                    do {
                        let hashes = try await ContactMatcher.hashedIdentifiers()
                        store.showToast(hashes.isEmpty ? "Contacts access is off — enable it in Settings" : "Hashed \(hashes.count) contact identifiers on-device · matching launches soon")
                    } catch { store.showToast("Couldn't read contacts", .error) }
                }
            } label: {
                row("📇", "Sync Contacts", "Find friends from your phone contacts", trailing: syncing ? AnyView(ProgressView()) : AnyView(Image(systemName: "chevron.right")))
            }
            .buttonStyle(.plain)
            ShareLink(item: url, subject: Text("Join me on RATED"), message: Text("Rank movies with me on RATED")) {
                row("🔗", "Share Invite Link", url.absoluteString, trailing: AnyView(Image(systemName: "chevron.right")))
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                RatedButton(title: "✉️ Email", style: .outline, small: true) {
                    openURL(URL(string: "mailto:?subject=Join%20me%20on%20RATED&body=\(url.absoluteString)")!)
                }
                RatedButton(title: "💬 SMS", style: .outline, small: true) {
                    openURL(URL(string: "sms:&body=Join%20me%20on%20RATED%20\(url.absoluteString)")!)
                }
            }
        }
    }

    private func row(_ icon: String, _ title: String, _ sub: String, trailing: AnyView) -> some View {
        HStack(spacing: 12) {
            T(icon).font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).mono(12, .bold).foregroundStyle(W.text)
                Text(sub).mono(9).foregroundStyle(W.dim).lineLimit(1)
            }
            Spacer()
            trailing.foregroundStyle(W.dim)
        }
        .card(radius: 12, padding: 12)
    }
}

private struct FindFriendsSettings: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    T("👥 Find People You Know").mono(13, .bold).foregroundStyle(W.text)
                    Text("See which of your friends are already on RATED, or invite them to join. We never post on your behalf.").mono(10).foregroundStyle(W.dim)
                }
                FindFriendsActions()
                Text("RATED only uses contact info to match you with friends already on the app. Contact data is hashed before leaving your device.").mono(9).foregroundStyle(W.dim)
            }
            .padding(18)
        }
    }
}

// MARK: - Notifications

private struct NotificationSettingsView: View {
    @AppStorage("notif.prefs") private var raw = ""
    @State private var prefs: [String: Bool] = [:]

    private static let defaults: [String: Bool] = [
        "push.new_follower": true, "push.follow_req": true, "push.watchlist_release": true, "push.friend_ranked": true,
        "push.friend_review": false, "push.streak_reminder": true,
        "email.weekly_digest": true, "email.new_follower": false, "email.watchlist_release": true, "email.marketing": false,
        "activity.likes": true, "activity.replies": true, "activity.rankings_milestone": true, "activity.streak_at_risk": true,
    ]

    private let sections: [(String, [(String, String, String)])] = [
        ("PUSH NOTIFICATIONS", [
            ("push.new_follower", "New follower", "When someone follows you"),
            ("push.follow_req", "Follow requests", "When someone requests to follow you"),
            ("push.watchlist_release", "Watchlist releases", "When a saved upcoming movie is out"),
            ("push.friend_ranked", "Friend ranked a movie", "Activity from people you follow"),
            ("push.friend_review", "Friend wrote a review", "When someone you follow posts a review"),
            ("push.streak_reminder", "Streak reminder", "Saturday reminder to rank before your streak breaks"),
        ]),
        ("EMAIL ALERTS", [
            ("email.weekly_digest", "Weekly digest", "Your ranking activity summary every Monday"),
            ("email.new_follower", "New follower", "Email when someone follows you"),
            ("email.watchlist_release", "Watchlist release", "Email when a watchlist movie drops"),
            ("email.marketing", "Product updates", "News and feature announcements from Rated"),
        ]),
        ("ACTIVITY ALERTS", [
            ("activity.likes", "Likes", "When someone likes your review or ranking"),
            ("activity.replies", "Replies", "When someone replies to your activity"),
            ("activity.rankings_milestone", "Ranking milestones", "When you hit 10, 50, 100 films ranked"),
            ("activity.streak_at_risk", "Streak at risk", "Alert 1 day before your streak resets"),
        ]),
    ]

    var body: some View {
        Form {
            ForEach(sections, id: \.0) { title, rows in
                Section {
                    ForEach(rows, id: \.0) { key, label, sub in
                        Toggle(isOn: Binding(get: { prefs[key] ?? Self.defaults[key] ?? false }, set: { set(key, $0) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label).mono(12, .semibold)
                                Text(sub).mono(9).foregroundStyle(W.dim)
                            }
                        }
                        .tint(W.accent)
                    }
                } header: { Text(title).mono(9, .bold) }
                .listRowBackground(W.card)
            }
        }
        .onAppear { prefs = (try? JSONDecoder().decode([String: Bool].self, from: Data(raw.utf8))) ?? Self.defaults }
    }

    private func set(_ key: String, _ on: Bool) {
        Haptics.light()
        prefs[key] = on
        raw = String(data: (try? JSONEncoder().encode(prefs)) ?? Data(), encoding: .utf8) ?? ""
        if key == "push.streak_reminder" { Task { await StreakReminder.set(on) } }
    }
}

/// Weekly local notification nudging the user to rank before Sunday's reset.
enum StreakReminder {
    static let id = "rated.streak.reminder"

    static func set(_ on: Bool) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard on, (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = "Keep your streak alive 🔥"
        content.body = "Rank one movie before Sunday to keep your weekly streak."
        var when = DateComponents()
        when.weekday = 7
        when.hour = 18
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Picker("Theme", selection: $store.themeMode) {
                    Text("Dark").tag(ThemeMode.dark)
                    Text("Light").tag(ThemeMode.light)
                    Text("System").tag(ThemeMode.system)
                }
                .pickerStyle(.segmented)
                .onChange(of: store.themeMode) { Haptics.light() }
                .accessibilityIdentifier("theme-picker")
            } header: { Text("THEME").mono(9, .bold) } footer: { Text("System follows your device's iOS setting.").mono(9) }
            .listRowBackground(W.card)
            Section {
                HStack {
                    ForEach([(0.9, 11.0), (1.0, 13.0), (1.15, 15.0), (1.3, 17.0)], id: \.0) { s, size in
                        Button { Haptics.light(); store.fontScale = s } label: {
                            Text("A").font(.system(size: size, weight: .bold, design: .monospaced))
                                .foregroundStyle(store.fontScale == s ? W.accent : W.dim)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(RoundedRectangle(cornerRadius: 10).fill(store.fontScale == s ? W.accentDim : W.bg))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: { Text("TEXT SIZE").mono(9, .bold) } footer: { Text("Scales all text. Current: \(Int(store.fontScale * 100))%").mono(9) }
            .listRowBackground(W.card)
        }
    }
}

// MARK: - About

private struct AboutSettings: View {
    @State private var apiBase = UserDefaults.standard.string(forKey: APIClient.baseOverrideKey) ?? ""
    @State private var reachable: Bool?

    var body: some View {
        Form {
            Section {
                ForEach([("Version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"),
                         ("Build", Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"),
                         ("Terms of Service", "rated.app/terms"), ("Privacy Policy", "rated.app/privacy")], id: \.0) { k, v in
                    HStack { Text(k).mono(11); Spacer(); Text(v).mono(11).foregroundStyle(W.dim) }
                }
            }
            .listRowBackground(W.card)
            Section {
                TextField(APIClient.shared.baseURL, text: $apiBase)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).mono(11)
                    .onSubmit(apply)
                HStack {
                    Button("Apply & Test", action: apply).mono(11, .bold)
                    Spacer()
                    if let r = reachable { Text(r ? "● reachable" : "● unreachable").mono(10, .bold).foregroundStyle(r ? W.green : W.accent) }
                }
            } header: { Text("DEVELOPER · API BASE URL").mono(9, .bold) } footer: {
                Text("Leave empty to use the build default. On a physical device, point this at your Mac's LAN IP (e.g. http://192.168.1.20:8010).").mono(9)
            }
            .listRowBackground(W.card)
        }
        .task { reachable = await APIClient.shared.ping() }
    }

    private func apply() {
        let v = apiBase.trimmingCharacters(in: .whitespaces)
        if v.isEmpty { UserDefaults.standard.removeObject(forKey: APIClient.baseOverrideKey) } else { UserDefaults.standard.set(v, forKey: APIClient.baseOverrideKey) }
        Task { reachable = nil; reachable = await APIClient.shared.ping() }
    }
}
