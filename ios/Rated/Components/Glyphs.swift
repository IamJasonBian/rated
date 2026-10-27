import SwiftUI

/// The web UI leans on emoji for icons. Natively we render those as SF Symbols
/// (crisper, tintable, and immune to emoji-font gaps such as the iOS 26.3
/// simulator, which draws them as "?" boxes). `T(_:)` builds a Text from a
/// string, swapping any mapped emoji for an inline symbol and leaving the rest
/// verbatim (so numbers aren't locale-grouped like `Text("\(int)")` would be).
enum Glyph {
    static let map: [Character: (String, Color?)] = [
        "🥇": ("medal.fill", Color(red: 0.92, green: 0.70, blue: 0.03)),
        "🥈": ("medal.fill", Color(white: 0.72)),
        "🥉": ("medal.fill", Color(red: 0.80, green: 0.50, blue: 0.20)),
        "🏆": ("trophy.fill", W.gold),
        "🔥": ("flame.fill", W.orange),
        "⚡": ("bolt.fill", nil),
        "🎬": ("film", nil),
        "👋": ("hand.wave.fill", W.gold),
        "👤": ("person.fill", nil),
        "👥": ("person.2.fill", nil),
        "🔔": ("bell.fill", nil),
        "🔒": ("lock.fill", nil),
        "📅": ("calendar", nil),
        "👀": ("eyes", nil),
        "📊": ("chart.bar.fill", nil),
        "🎟": ("ticket.fill", nil),
        "✏️": ("pencil", nil),
        "⚠️": ("exclamationmark.triangle.fill", W.orange),
        "🚫": ("nosign", W.accent),
        "🌿": ("leaf.fill", W.green),
        "💎": ("diamond.fill", W.blue),
        "📥": ("tray.and.arrow.down.fill", nil),
        "📭": ("tray", nil),
        "⭐": ("star.fill", W.gold),
        "📺": ("tv", nil),
        "🔴": ("play.rectangle.fill", W.accent),
        "🕒": ("clock", nil),
        "🎭": ("theatermasks.fill", nil),
        "🚀": ("sparkles", nil),
        "😱": ("moon.stars.fill", nil),
        "😂": ("face.smiling", nil),
        "💥": ("burst.fill", nil),
        "🌏": ("globe.asia.australia.fill", nil),
        "📇": ("person.crop.rectangle.stack.fill", nil),
        "🔗": ("link", nil),
        "✉️": ("envelope.fill", nil),
        "💬": ("bubble.left.fill", nil),
        "🌙": ("moon.fill", nil),
        "☀️": ("sun.max.fill", nil),
        "⚙️": ("gearshape.fill", nil),
        "⏳": ("hourglass", W.orange),
        "🗑️": ("trash", nil),
        "🎨": ("paintpalette.fill", nil),
        "ℹ️": ("info.circle.fill", nil),
        "📡": ("antenna.radiowaves.left.and.right", nil),
    ]
}

func T(_ s: String) -> Text {
    var out = Text(verbatim: "")
    var buf = ""
    for ch in s {
        if let (name, color) = Glyph.map[ch] {
            if !buf.isEmpty { out = out + Text(verbatim: buf); buf = "" }
            let img = Text(Image(systemName: name))
            out = out + (color.map { img.foregroundColor($0) } ?? img)
        } else {
            buf.append(ch)
        }
    }
    return buf.isEmpty ? out : out + Text(verbatim: buf)
}
