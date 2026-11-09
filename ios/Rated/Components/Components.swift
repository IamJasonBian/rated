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
        Text(height < 80 ? "" : title ?? "")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(W.dim)
            .multilineTextAlignment(.center)
            .padding(4)
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
        Text(verbatim: text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.15)))
            .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 1))
            .fixedSize()
    }
}

struct AvatarView: View {
    var initial: String
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle().fill(W.border)
            Text(initial).font(.title2.weight(.semibold)).foregroundStyle(W.text).lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(verbatim: text).font(.subheadline.weight(.semibold)).foregroundStyle(W.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Extends a small control's tappable area past its visual bounds without moving layout.
    func hitArea(_ inset: CGFloat = 14) -> some View {
        contentShape(Rectangle().inset(by: -inset))
    }
}

struct Chip: View {
    var label: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: { Haptics.light(); action() }) {
            Text(verbatim: label).font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? W.accent : W.dim)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(selected ? W.accentDim : W.card))
                .overlay(Capsule().stroke(selected ? W.accent : W.border, lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
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
            Text(verbatim: title)
                .font(small ? .subheadline.weight(.semibold) : .headline)
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

/// Segmented underline tab bar used by Profile.
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
                        Text(verbatim: label).font(.subheadline.weight(.semibold))
                            .foregroundStyle(selection == key ? W.accent : W.dim)
                        Rectangle().fill(selection == key ? W.accent : .clear).frame(height: 2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .bottom)
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
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Text(verbatim: title).font(.subheadline.weight(.semibold)).foregroundStyle(W.text)
            Text(verbatim: subtitle).font(.subheadline).foregroundStyle(W.dim).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

/// Pulsing placeholder block (components/Skeleton.jsx).
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat
    var radius: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(W.border)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .opacity(dim ? 0.4 : 0.9)
            .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { dim = true } } }
    }
}

/// Toast banner pinned above the tab bar.
struct ToastView: View {
    var toast: Toast

    var body: some View {
        Text(verbatim: toast.message)
            .font(.subheadline.weight(.semibold))
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
                Text("Close").font(.body.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
            }
            .hitArea()
            .padding()
        }
    }
}

struct IdentifiableURL: Identifiable {
    var url: URL
    var id: String { url.absoluteString }
}
