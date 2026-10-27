import SafariServices
import SwiftUI

/// Poster with a titled placeholder while loading or when the URL is missing (components/Poster.jsx).
struct PosterView: View {
    var url: String?
    var title: String?
    var width: CGFloat?
    var height: CGFloat
    var radius: CGFloat = 8

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius).fill(W.border.opacity(0.6))
            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Text(title ?? "🎬")
            .mono(max(7, min(11, height / 9)), .bold)
            .foregroundStyle(W.dim)
            .multilineTextAlignment(.center)
            .padding(4)
            .minimumScaleFactor(0.6)
    }
}

enum BadgeColor { case red, purple, orange, gold, green, blue }

struct BadgeView: View {
    var text: String
    var color: BadgeColor = .red

    private var tint: Color {
        switch color {
        case .red: W.accent
        case .purple: W.purple
        case .orange: W.orange
        case .gold: W.gold
        case .green: W.green
        case .blue: W.blue
        }
    }

    var body: some View {
        T(text)
            .mono(8, .heavy)
            .foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.15)))
            .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 1))
    }
}

struct AvatarView: View {
    var initial: String
    var size: CGFloat = 32
    var image: Data?

    var body: some View {
        ZStack {
            Circle().fill(W.border)
            if let image, let ui = UIImage(data: image) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Text(initial).mono(size * 0.4, .bold).foregroundStyle(W.text)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct SectionLabel: View {
    var text: String
    var body: some View {
        T(text).mono(9, .bold).tracking(1).foregroundStyle(W.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Chip: View {
    var label: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: { Haptics.light(); action() }) {
            T(label).mono(10, .semibold)
                .foregroundStyle(selected ? W.accent : W.dim)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(selected ? W.accentDim : W.card))
                .overlay(Capsule().stroke(selected ? W.accent : W.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Primary / secondary pill button (components/Btn.jsx).
struct RatedButton: View {
    enum Style { case accent, outline, tinted(Color) }
    var title: String
    var style: Style = .accent
    var small = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            T(title)
                .mono(small ? 10 : 12, .black)
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity, minHeight: small ? 36 : 48)
                .background(RoundedRectangle(cornerRadius: small ? 10 : 12).fill(bg))
                .overlay(RoundedRectangle(cornerRadius: small ? 10 : 12).stroke(stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var fg: Color {
        switch style {
        case .accent: .white
        case .outline: W.text
        case .tinted(let c): c
        }
    }
    private var bg: Color {
        switch style {
        case .accent: W.accent
        case .outline: W.card
        case .tinted(let c): c.opacity(0.13)
        }
    }
    private var stroke: Color {
        switch style {
        case .accent: .clear
        case .outline: W.border
        case .tinted(let c): c.opacity(0.6)
        }
    }
}

/// Segmented underline tab bar used by Home, Leaderboard, Profile and Notifications.
struct UnderlineTabs<Key: Hashable>: View {
    var tabs: [(Key, String)]
    @Binding var selection: Key

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.0) { key, label in
                Button {
                    Haptics.light()
                    withAnimation(.snappy) { selection = key }
                } label: {
                    VStack(spacing: 6) {
                        Text(label).mono(10, .semibold)
                            .foregroundStyle(selection == key ? W.accent : W.dim)
                        Rectangle().fill(selection == key ? W.accent : .clear).frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == key ? .isSelected : [])
                .accessibilityIdentifier("tab-\(key)")
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(W.border).frame(height: 1) }
    }
}

struct EmptyStateView: View {
    var icon: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            T(icon).font(.system(size: 30))
            T(title).mono(12, .bold).foregroundStyle(W.text)
            T(subtitle).mono(10).foregroundStyle(W.dim).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

struct FollowPill: View {
    var following: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(following ? "FOLLOWING" : "+ FOLLOW")
                .mono(8, .heavy)
                .foregroundStyle(following ? W.dim : .white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(following ? Color.clear : W.accent))
                .overlay(Capsule().stroke(following ? W.border : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Pulsing placeholder block (components/Skeleton.jsx).
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat
    var radius: CGFloat = 6
    @State private var dim = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(W.border)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .opacity(dim ? 0.4 : 0.9)
            .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { dim = true } }
    }
}

/// Toast banner pinned above the tab bar.
struct ToastView: View {
    var toast: Toast

    var body: some View {
        T(toast.message)
            .mono(11, .semibold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(toast.tone == .error ? W.accent : toast.tone == .warn ? W.orange : Color.black))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(W.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("toast")
    }
}

/// `⋯` menu offering report (with reason picker) and block — components/ReportBlockMenu.jsx.
struct ReportBlockMenu: View {
    @Environment(AppStore.self) private var store
    var targetType: String
    var targetId: String
    var targetLabel: String
    var targetUser: String?
    @State private var showReasons = false
    @State private var confirmBlock = false

    var body: some View {
        Menu {
            Button("Report…", systemImage: "flag") { showReasons = true }
            if let u = targetUser, !store.blockedUsers.contains(u) {
                Button("Block \(u)", systemImage: "hand.raised", role: .destructive) { confirmBlock = true }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(W.dim)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More options")
        .confirmationDialog("Why are you reporting this?", isPresented: $showReasons, titleVisibility: .visible) {
            ForEach(Mock.reportReasons) { r in
                Button(r.label) { store.report(type: targetType, targetId: targetId, label: targetLabel, reason: r) }
            }
        } message: {
            Text("Reports are anonymous. We review every one.")
        }
        .alert("Block \(targetUser ?? "")?", isPresented: $confirmBlock) {
            Button("Cancel", role: .cancel) {}
            Button("Block", role: .destructive) { if let u = targetUser { store.block(u) } }
        } message: {
            Text("They won't be able to see your profile or follow you, and you'll stop seeing their activity.")
        }
    }
}

/// In-app Safari for trailers and external links.
struct SafariView: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

/// Full-screen pinch-to-zoom image viewer (components/ImageViewer.jsx).
struct ImageViewer: View {
    var url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { img in
                img.resizable().scaledToFit()
            } placeholder: { ProgressView().tint(.white) }
                .scaleEffect(scale * pinch)
                .gesture(MagnifyGesture().updating($pinch) { v, s, _ in s = v.magnification }
                    .onEnded { v in scale = max(1, min(4, scale * v.magnification)) })
                .onTapGesture(count: 2) { withAnimation { scale = scale > 1 ? 1 : 2 } }
        }
        .onTapGesture { dismiss() }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 28)).foregroundStyle(.white.opacity(0.8))
            }
            .padding()
            .accessibilityLabel("Close")
        }
    }
}

struct IdentifiableURL: Identifiable {
    var url: URL
    var id: String { url.absoluteString }
}

enum ShareLinks {
    static func movie(_ m: Movie) -> URL { URL(string: "https://rated.app/movie/\(m.id)")! }
    static func profile(_ username: String) -> URL { URL(string: "https://rated.app/\(username)")! }
    static func invite(_ username: String) -> URL { URL(string: "https://rated.app/invite/\(username.isEmpty ? "you" : username)")! }
}
