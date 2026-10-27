import SwiftUI

struct LoginView: View {
    @Environment(AppStore.self) private var store
    @State private var busy: LoginProvider?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 8) {
                Text("RATED").mono(46, .black).tracking(-2).foregroundStyle(W.accent)
                    .shadow(color: W.accent.opacity(0.35), radius: 24)
                Text("YOUR TASTE. RANKED.").mono(10).tracking(3).foregroundStyle(W.dim)
            }
            .padding(.bottom, 44)
            VStack(spacing: 10) {
                loginButton(.apple, title: "Continue with Apple", icon: "applelogo", fg: .black, bg: .white)
                loginButton(.google, title: "Continue with Google", icon: "g.circle.fill", fg: W.text, bg: W.card)
            }
            Text("By continuing you agree to Rated's **Terms** & **Privacy**")
                .mono(9).foregroundStyle(W.dim).multilineTextAlignment(.center).padding(.top, 28)
            Spacer()
            Text("Apple ID & Google only · Import watch history from 8 platforms")
                .mono(9).foregroundStyle(W.dim).padding(.bottom, 12)
        }
        .padding(.horizontal, 28)
    }

    private func loginButton(_ p: LoginProvider, title: String, icon: String, fg: Color, bg: Color) -> some View {
        Button {
            Haptics.medium()
            busy = p
            Task { await store.login(p); busy = nil }
        } label: {
            HStack(spacing: 10) {
                if busy == p { ProgressView().tint(fg) } else { Image(systemName: icon).font(.system(size: 17, weight: .semibold)) }
                Text(title).font(.system(size: 15, weight: .semibold))
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

    private var localErr: String? { Usernames.localError(value) }
    private var available: Bool { localErr == nil && serverAvailable == true && !checking && value.count >= 4 }
    private var errorMsg: String? { localErr ?? (serverAvailable == false && !checking ? "Username already taken" : nil) }

    var body: some View {
        VStack(spacing: 0) {
            if confirmed {
                VStack(spacing: 12) {
                    T("🎬").font(.system(size: 52))
                    Text("@\(value)").mono(24, .black).foregroundStyle(W.accent)
                    Text("Welcome to RATED").mono(12).foregroundStyle(W.dim)
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
        .animation(.snappy, value: step)
        .animation(.spring, value: confirmed)
        .onAppear { focused = true; if name.isEmpty, !store.displayName.isEmpty, store.displayName != "Apple User", store.displayName != "Google User" { name = store.displayName } }
    }

    private var nameStep: some View {
        let valid = name.trimmingCharacters(in: .whitespaces).count >= 2 && Profanity.check(name) == nil
        return VStack(spacing: 14) {
            Text("RATED").mono(28, .black).foregroundStyle(W.accent)
            T("👋").font(.system(size: 26)).frame(width: 54, height: 54)
                .background(Circle().fill(W.card)).overlay(Circle().stroke(W.border, lineWidth: 2))
            Text("What's your name?").mono(16, .heavy).foregroundStyle(W.text)
            Text("Signed in with \(store.provider == .apple ? "Apple" : "Google").\nThis is how you'll appear on your profile.")
                .mono(10).foregroundStyle(W.dim).multilineTextAlignment(.center)
            HStack {
                Text("YOUR NAME").mono(10).foregroundStyle(W.dim)
                Spacer()
                Text("\(name.count) / 30").mono(9).foregroundStyle(name.count >= 27 ? W.accent : W.dim)
            }
            .padding(.top, 14)
            TextField("e.g. Stephanie", text: $name)
                .focused($focused)
                .submitLabel(.next)
                .onSubmit { continueFromName() }
                .onChange(of: name) { _, v in if v.count > 30 { name = String(v.prefix(30)) }; nameError = nil }
                .mono(15).foregroundStyle(W.text)
                .card(radius: 12, stroke: nameError != nil || Profanity.check(name) != nil ? W.accent : W.border, padding: 14)
                .accessibilityIdentifier("name-field")
            Text(nameError.map { "✗ \($0)" } ?? (Profanity.check(name) != nil ? "✗ Name contains inappropriate language" : "Can be your real name or a nickname · changeable later"))
                .mono(9).foregroundStyle(nameError != nil || Profanity.check(name) != nil ? W.accent : W.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
            RatedButton(title: "CONTINUE →", style: valid ? .accent : .outline) { continueFromName() }
                .opacity(valid ? 1 : 0.5)
                .accessibilityIdentifier("name-continue")
        }
    }

    private var usernameStep: some View {
        VStack(spacing: 12) {
            Text("RATED").mono(28, .black).foregroundStyle(W.accent)
            HStack(spacing: 6) {
                Text("Hi,").mono(11).foregroundStyle(W.dim)
                Text(name.trimmingCharacters(in: .whitespaces)).mono(11, .bold).foregroundStyle(W.text)
                Button { step = 0 } label: { Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(W.dim) }
                    .accessibilityLabel("Edit name")
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(W.card)).overlay(Capsule().stroke(W.border))
            Text("Now pick a username").mono(16, .heavy).foregroundStyle(W.text)
            Text("This is your unique @handle on RATED.").mono(10).foregroundStyle(W.dim)
            HStack(spacing: 4) {
                Text("@").mono(14).foregroundStyle(W.dim)
                TextField("username", text: $value)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit { claim() }
                    .mono(15).foregroundStyle(W.text)
                    .accessibilityIdentifier("username-field")
                Group {
                    if checking { ProgressView().controlSize(.small) }
                    else if available { Image(systemName: "checkmark").foregroundStyle(W.green) }
                    else if errorMsg != nil && !value.isEmpty { Image(systemName: "xmark").foregroundStyle(W.accent) }
                }
                .frame(width: 20)
            }
            .card(radius: 12, stroke: errorMsg != nil && !value.isEmpty ? W.accent : available ? W.green : W.border, padding: 14)
            .padding(.top, 8)
            .onChange(of: value) { _, raw in onChange(raw) }
            VStack(alignment: .leading, spacing: 4) {
                Text("4–20 chars · lowercase letters, numbers, underscore only").mono(10).foregroundStyle(W.dim)
                if let e = errorMsg, !checking, !value.isEmpty { Text("✗ \(e)").mono(10).foregroundStyle(W.accent) }
                if available { Text("@\(value) is available ✓").mono(10).foregroundStyle(W.green) }
                if let e = claimError { Text(e).mono(10).foregroundStyle(W.accent) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if errorMsg == "Username already taken", value.count >= 4 {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "TRY ONE OF THESE")
                    HStack {
                        ForEach(["\(value)_", "\(value)1", "\(value)42", "the_\(value)"].filter { !Usernames.taken.contains($0) && $0.count <= 20 }.prefix(4), id: \.self) { s in
                            Chip(label: "@\(s)", selected: false) { value = s }
                        }
                    }
                }
            }
            RatedButton(title: "CLAIM @\(value.isEmpty ? "username" : value) →", style: available ? .accent : .outline) { claim() }
                .opacity(available ? 1 : 0.5)
                .padding(.top, 6)
                .accessibilityIdentifier("username-claim")
            Text("Your username is public · You can change it once every 30 days").mono(9).foregroundStyle(W.dim)
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
            serverAvailable = res ?? !Usernames.taken.contains(clean)
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
            Usernames.taken.insert(value)
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
                Text("STEP 1 OF 1 · WELCOME").mono(9, .bold).tracking(1.5).foregroundStyle(W.accent)
                Text("Rank your first \(target) movies").mono(21, .black).foregroundStyle(W.text)
                Text("Tap a movie you've seen — we'll ask you to compare it to others to figure out exactly where it ranks. The more you rank, the smarter your taste profile gets.")
                    .mono(11).foregroundStyle(W.dim).lineSpacing(3)
            }
            .padding(.horizontal, 22).padding(.top, 16)
            VStack(spacing: 6) {
                HStack {
                    Text(ready ? "✓ READY" : "\(count) / \(target) RANKED").mono(10, .bold).foregroundStyle(ready ? W.green : W.dim)
                        .accessibilityIdentifier("onboarding-progress")
                    Spacer()
                    if !ready { Text("\(target - count) more to go").mono(9).foregroundStyle(W.dim) }
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
                        .mono(12).foregroundStyle(W.text)
                        .card(radius: 12, padding: 11)
                        .submitLabel(.search)
                    if popular == nil && query.count < 2 { ProgressView("Loading popular films…").padding(40) }
                    if query.count >= 2 && !searching && (results ?? []).isEmpty { Text("No results for \"\(query)\"").mono(10).foregroundStyle(W.dim).padding() }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        ForEach(query.count >= 2 ? (results ?? []) : (popular ?? [])) { m in
                            let ranked = store.rankedIds.contains(m.id)
                            Button { store.startRank(m) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    PosterView(url: m.posterURL, title: m.title, height: 200)
                                        .overlay(alignment: .topTrailing) { if ranked { BadgeView(text: "✓ RANKED", color: .green).padding(6) } }
                                    Text(m.title).mono(11, .bold).foregroundStyle(W.text).lineLimit(2).frame(height: 30, alignment: .topLeading)
                                    Text(m.releaseYear.map(String.init) ?? "").mono(9).foregroundStyle(W.dim)
                                    Text(ranked ? "RANKED" : "⚡ RANK THIS").mono(10, .bold).foregroundStyle(.white)
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
            HStack {
                if ready {
                    RatedButton(title: "✓ DONE — TAKE ME HOME") { Haptics.heavy(); store.finishOnboarding() }
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
            results = await Catalog.shared.search(query)
            searching = false
        }
    }
}
