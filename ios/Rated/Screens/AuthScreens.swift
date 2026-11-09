import SwiftUI

struct LoginView: View {
    @Environment(AppStore.self) private var store
    @State private var busy: LoginProvider?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Rated").font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                .padding(.bottom, 40)
            VStack(spacing: 10) {
                loginButton(.apple, title: "Continue with Apple", fg: .black, bg: .white)
                loginButton(.google, title: "Continue with Google", fg: .white, bg: .black)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 28)
        .background {
            ZStack {
                LoopingVideoBackground(video: "login-loop", poster: "login-poster.jpg")
                Color.black.opacity(0.3)
            }
            .ignoresSafeArea()
        }
    }

    private func loginButton(_ p: LoginProvider, title: String, fg: Color, bg: Color) -> some View {
        Button {
            Haptics.medium()
            busy = p
            Task { await store.login(p); busy = nil }
        } label: {
            HStack(spacing: 10) {
                if busy == p { ProgressView().tint(fg) }
                Text(title).font(.headline)
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 12).fill(bg))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(W.border, lineWidth: p == .google ? 1 : 0))
        }
        .buttonStyle(.plain)
        .disabled(busy != nil)
        .accessibilityIdentifier("login-\(p.rawValue)")
    }
}

/// Two-step name → @handle chooser with debounced server availability check (UsernameScreen.jsx).
struct UsernameView: View {
    @Environment(AppStore.self) private var store
    @State private var step = 0
    @State private var name = ""
    @State private var nameError: String?
    @State private var value = ""
    @State private var checking = false
    @State private var serverAvailable: Bool?
    @State private var claimError: String?
    @State private var confirmed = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var localErr: String? { Usernames.localError(value) }
    private var available: Bool { localErr == nil && serverAvailable == true && !checking && value.count >= 4 }
    private var errorMsg: String? { localErr ?? (serverAvailable == false && !checking ? "Username already taken" : nil) }

    var body: some View {
        VStack(spacing: 0) {
            if confirmed {
                VStack(spacing: 12) {
                    Text("@\(value)").font(.title.weight(.bold)).foregroundStyle(W.accent)
                    Text("Welcome to Rated").font(.subheadline).foregroundStyle(W.dim)
                }
                .transition(.scale.combined(with: .opacity))
            } else if step == 0 {
                nameStep
            } else {
                usernameStep
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 28)
        .animation(reduceMotion ? nil : .snappy, value: step)
        .animation(reduceMotion ? nil : .spring, value: confirmed)
        .onAppear { focused = true; if name.isEmpty, !store.displayName.isEmpty, store.displayName != "Apple User", store.displayName != "Google User" { name = store.displayName } }
    }

    private var nameStep: some View {
        let valid = name.trimmingCharacters(in: .whitespaces).count >= 2 && Profanity.check(name) == nil
        return VStack(spacing: 14) {
            Text("Rated").font(.title.weight(.bold)).foregroundStyle(W.text)
            Text("What's your name?").font(.title3.weight(.semibold)).foregroundStyle(W.text)
            TextField("e.g. Stephanie", text: $name)
                .focused($focused)
                .submitLabel(.next)
                .onSubmit { continueFromName() }
                .onChange(of: name) { _, v in if v.count > 30 { name = String(v.prefix(30)) }; nameError = nil }
                .font(.body).foregroundStyle(W.text)
                .card(radius: 12, stroke: nameError != nil || Profanity.check(name) != nil ? W.accent : W.border, padding: 14)
                .accessibilityIdentifier("name-field")
            if let e = nameError ?? (Profanity.check(name) != nil ? "Name contains inappropriate language" : nil) {
                Text(e).font(.subheadline).foregroundStyle(W.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            RatedButton(title: "Continue", style: valid ? .accent : .outline) { continueFromName() }
                .opacity(valid ? 1 : 0.5)
                .accessibilityIdentifier("name-continue")
        }
    }

    private var usernameStep: some View {
        VStack(spacing: 12) {
            Text("Rated").font(.title.weight(.bold)).foregroundStyle(W.text)
            HStack(spacing: 6) {
                Text("Hi,").font(.subheadline).foregroundStyle(W.dim)
                Text(name.trimmingCharacters(in: .whitespaces)).font(.subheadline.weight(.semibold)).foregroundStyle(W.text)
                Button { step = 0 } label: { Text("Edit").font(.subheadline).foregroundStyle(W.accent) }
                    .hitArea()
                    .accessibilityLabel("Edit name")
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(W.card)).overlay(Capsule().stroke(W.border))
            Text("Now pick a username").font(.title3.weight(.semibold)).foregroundStyle(W.text)
            HStack(spacing: 4) {
                Text("@").font(.subheadline).foregroundStyle(W.dim)
                TextField("username", text: $value)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit { claim() }
                    .font(.body).foregroundStyle(W.text)
                    .accessibilityIdentifier("username-field")
                Group {
                    if checking { ProgressView().controlSize(.small) }
                }
                .frame(width: 20)
            }
            .card(radius: 12, stroke: errorMsg != nil && !value.isEmpty ? W.accent : available ? W.green : W.border, padding: 14)
            .padding(.top, 8)
            .onChange(of: value) { _, raw in onChange(raw) }
            VStack(alignment: .leading, spacing: 4) {
                if let e = errorMsg, !checking, !value.isEmpty { Text(e).font(.subheadline).foregroundStyle(W.accent) }
                if available { Text("@\(value) is available").font(.subheadline).foregroundStyle(W.green) }
                if let e = claimError { Text(e).font(.subheadline).foregroundStyle(W.accent) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if errorMsg == "Username already taken", value.count >= 4 {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Try one of these")
                    ScrollView(.horizontal, showsIndicators: false) { HStack {
                        ForEach(["\(value)_", "\(value)1", "\(value)42", "the_\(value)"].filter { $0.count <= 20 }.prefix(4), id: \.self) { s in
                            Chip(label: "@\(s)", selected: false) { value = s }
                        }
                    } }
                }
            }
            RatedButton(title: "Claim @\(value.isEmpty ? "username" : value)", style: available ? .accent : .outline) { claim() }
                .opacity(available ? 1 : 0.5)
                .padding(.top, 6)
                .accessibilityIdentifier("username-claim")
            Text("Your username is public").font(.subheadline).foregroundStyle(W.dim)
        }
    }

    private func continueFromName() {
        let t = name.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { nameError = "Please enter your name"; return }
        if t.count < 2 { nameError = "Name must be at least 2 characters"; return }
        if Profanity.check(t) != nil { nameError = "Name contains inappropriate language"; return }
        Haptics.light()
        step = 1
    }

    private func onChange(_ raw: String) {
        let clean = String(Usernames.sanitize(raw).prefix(20))
        if clean != raw { value = clean; return }
        serverAvailable = nil
        claimError = nil
        guard clean.count >= 4, Usernames.localError(clean) == nil else { checking = false; return }
        checking = true
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard value == clean else { return }
            let res = await APIClient.shared.checkUsername(clean)
            guard value == clean else { return }
            serverAvailable = res
            checking = false
        }
    }

    private func claim() {
        guard available else { return }
        Task {
            if let s = store.session {
                do { try await APIClient.shared.setUsername(value, token: s) }
                catch { claimError = error.localizedDescription; return }
            }
            Haptics.success()
            confirmed = true
            try? await Task.sleep(for: .milliseconds(900))
            await store.completeUsername(value, name: name.trimmingCharacters(in: .whitespaces))
        }
    }
}

/// First-run tutorial: rank 5 films before the app opens up (OnboardingRank.jsx).
struct OnboardingRankView: View {
    @Environment(AppStore.self) private var store
    @State private var popular: [Movie]?
    @State private var query = ""
    @State private var results: [Movie]?
    @State private var searching = false
    private let target = 5

    var body: some View {
        let count = store.rankedIds.count
        let ready = count >= target
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Rank your first \(target) movies").font(.title2.weight(.bold)).foregroundStyle(W.text)
                Text("Tap a movie you've seen, then compare it with others to find where it ranks.")
                    .font(.subheadline).foregroundStyle(W.dim).lineSpacing(3)
            }
            .padding(.horizontal, 22).padding(.top, 16)
            VStack(spacing: 6) {
                HStack {
                    Text(ready ? "READY" : "\(count) / \(target) RANKED").font(.subheadline.weight(.semibold)).foregroundStyle(ready ? W.green : W.dim)
                        .accessibilityIdentifier("onboarding-progress")
                    Spacer()
                }
                ProgressView(value: min(1, Double(count) / Double(target)))
                    .tint(ready ? W.green : W.accent)
                    .animation(.snappy, value: count)
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
            Divider().overlay(W.border)
            ScrollView {
                VStack(spacing: 10) {
                    TextField("Or search for a movie you've seen...", text: $query)
                        .font(.body).foregroundStyle(W.text)
                        .card(radius: 12, padding: 11)
                        .submitLabel(.search)
                    if popular == nil && query.count < 2 { ProgressView("Loading popular films…").padding(40) }
                    if popular?.isEmpty == true && query.count < 2 { EmptyStateView(title: "Couldn't load movies", subtitle: "Check your connection, or skip for now.") }
                    if query.count >= 2 && !searching && (results ?? []).isEmpty { Text("No results for \"\(query)\"").font(.subheadline).foregroundStyle(W.dim).padding() }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        ForEach(query.count >= 2 ? (results ?? []) : (popular ?? [])) { m in
                            let ranked = store.rankedIds.contains(m.id)
                            Button { store.startRank(m) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    PosterView(url: m.posterURL, title: m.title, height: 200)
                                        .overlay(alignment: .topTrailing) { if ranked { BadgeView(text: "Ranked", color: .green).padding(6) } }
                                    Text(m.title).font(.subheadline.weight(.semibold)).foregroundStyle(W.text).lineLimit(2).frame(minHeight: 42, alignment: .topLeading)
                                    Text(ranked ? "Ranked" : "Rank This").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(ranked ? W.green : W.accent))
                                }
                                .card(radius: 12, padding: 8)
                            }
                            .buttonStyle(.plain)
                            .disabled(ranked)
                            .accessibilityIdentifier("onboard-\(m.id)")
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            HStack {
                if ready {
                    RatedButton(title: "Done — Take Me Home") { Haptics.heavy(); store.finishOnboarding() }
                        .accessibilityIdentifier("onboarding-done")
                } else {
                    RatedButton(title: "Skip for now", style: .outline) { Haptics.light(); store.finishOnboarding() }
                        .accessibilityIdentifier("onboarding-skip")
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
            .background(W.bg)
            .overlay(alignment: .top) { Rectangle().fill(W.border).frame(height: 1) }
        }
        .task { popular = Array(await Catalog.shared.popular().prefix(10)) }
        .task(id: query) {
            guard query.count >= 2 else { results = nil; return }
            searching = true
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            results = await Catalog.shared.search(query) ?? []
            searching = false
        }
    }
}
