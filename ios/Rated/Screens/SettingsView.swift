import SwiftUI

enum SettingsSection: String, CaseIterable, Hashable, Identifiable {
    case account, about
    var id: String { rawValue }

    var label: String { ["Account", "About"][Self.allCases.firstIndex(of: self)!] }
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
                        HStack(spacing: 6) {
                            Text(s.label).foregroundStyle(W.text)
                        }
                    }
                    .accessibilityIdentifier("settings-\(s.rawValue)")
                }
            }
            .listRowBackground(W.card)
            Section {
                Button(role: .destructive) { store.signOut() } label: {
                    Text("Sign Out").frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("sign-out")
            }
            .listRowBackground(W.card)
        }
        .scrollContentBackground(.hidden)
        .background(W.bg)
        .navigationTitle("Settings")
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
    @State private var newUsername = ""
    @State private var status: String?
    @State private var saved = false
    @State private var profileError: String?
    @State private var deleteStep = 0
    @State private var deleteText = ""

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("Display Name").font(.subheadline.weight(.semibold)).foregroundStyle(W.dim); Spacer(); Text("\(name.count)/30").font(.subheadline).foregroundStyle(W.dim) }
                    TextField("Your full name", text: $name)
                        .onChange(of: name) { _, v in if v.count > 30 { name = String(v.prefix(30)) } }
                        .accessibilityIdentifier("display-name")
                }
                if let e = profileError { Text(e).font(.subheadline).foregroundStyle(W.accent) }
                Button(saved ? "✓ SAVED" : "Save Profile") { saveProfile() }.foregroundStyle(saved ? W.green : W.accent)
                    .accessibilityIdentifier("save-profile")
            } header: { sectionHeader("Edit Profile") }
            .listRowBackground(W.card)

            Section {
                HStack(spacing: 4) {
                    Text("@").foregroundStyle(W.dim)
                    TextField("username", text: $newUsername).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: newUsername) { _, v in check(v) }
                        .accessibilityIdentifier("change-username")
                    Text(statusLabel).font(.subheadline.weight(.semibold)).foregroundStyle(status == "available" ? W.green : W.dim)
                }
                Button("Save Username") {
                    Task { if await store.changeUsername(newUsername) { status = "updated"; Haptics.success() } }
                }
                .disabled(status != "available")
                .accessibilityIdentifier("save-username")
            } header: { sectionHeader("Change Username") }
            .listRowBackground(W.card)

            Section {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.email ?? (store.provider == .apple ? "user@icloud.com" : "user@gmail.com"))
                        Text("Connected via \(store.provider == .apple ? "Apple" : "Google")").font(.subheadline).foregroundStyle(W.dim)
                    }
                }
            } header: { sectionHeader("Connected Account") }
            .listRowBackground(W.card)

            Section {
                Button(role: .destructive) { deleteText = ""; deleteStep = 1 } label: {
                    Text("Delete Account")
                }
                .accessibilityIdentifier("delete-account")
            }
            .listRowBackground(W.card)
        }
        .onAppear { name = store.displayName; newUsername = store.username }
        .alert("Delete Account?", isPresented: Binding(get: { deleteStep == 1 }, set: { if !$0 && deleteStep == 1 { deleteStep = 0 } })) {
            Button("Keep Account", role: .cancel) { deleteStep = 0 }
            Button("Continue", role: .destructive) { Task { try? await Task.sleep(for: .milliseconds(350)); deleteStep = 2 } }
        } message: {
            Text("This will permanently erase your rankings and reviews, remove your profile and username, and delete your saved films. This cannot be undone.")
        }
        .alert("Final Confirmation", isPresented: Binding(get: { deleteStep == 2 }, set: { if !$0 { deleteStep = 0 } })) {
            TextField("Type DELETE to confirm", text: $deleteText)
            Button("Cancel", role: .cancel) { deleteStep = 0 }
            Button("Delete Forever", role: .destructive) {
                if deleteText == "DELETE" { Task { await store.deleteAccount() } } else { store.showToast("Type DELETE exactly to confirm", .error) }
            }
        } message: { Text("To confirm, type DELETE below.") }
    }

    private var statusLabel: String {
        ["available": "available", "taken": "taken", "invalid": "too short", "profane": "blocked", "checking": "…", "updated": "updated"][status ?? ""] ?? ""
    }

    private func saveProfile() {
        if Profanity.check(name) != nil { profileError = "Display name contains inappropriate language. Please revise it."; return }
        profileError = nil
        store.updateProfile(name: name.trimmingCharacters(in: .whitespaces))
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
            let res = await APIClient.shared.checkUsername(clean)
            guard newUsername == clean else { return }
            status = res.map { $0 ? "available" : "taken" }
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
                         ("Build", Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")], id: \.0) { k, v in
                    HStack { Text(k); Spacer(); Text(v).foregroundStyle(W.dim) }
                }
            }
            .listRowBackground(W.card)
            Section {
                TextField(APIClient.shared.baseURL, text: $apiBase)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .onSubmit(apply)
                HStack {
                    Button("Apply & Test", action: apply)
                    Spacer()
                    if let r = reachable { Text(r ? "● reachable" : "● unreachable").font(.subheadline.weight(.semibold)).foregroundStyle(r ? W.green : W.accent) }
                }
            } header: { sectionHeader("Developer · API Base URL") } footer: {
                Text(verbatim: "Leave empty to use the build default. On a physical device, point this at your Mac's LAN IP (e.g. http://192.168.1.20:8010).").font(.subheadline)
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

private func sectionHeader(_ title: String) -> some View {
    Text(title).font(.subheadline.weight(.semibold)).textCase(nil)
}
