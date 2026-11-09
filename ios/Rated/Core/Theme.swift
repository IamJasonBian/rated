import SwiftUI
import UIKit

// Palette mirrors build/src/theme.js (DARK_THEME / LIGHT_THEME). Each color is
// a dynamic UIColor so flipping `.preferredColorScheme` re-themes the whole
// tree without prop-drilling — the SwiftUI equivalent of the web's W Proxy.
enum W {
    static let bg = dyn(light: 0xf7f7fa, dark: 0x0f0f13)
    static let card = dyn(light: 0xffffff, dark: 0x1a1a22)
    static let border = dyn(light: 0xe5e5ec, dark: 0x2c2c3a)
    static let text = dyn(light: 0x18181e, dark: 0xededf2)
    static let dim = dyn(light: 0x6e6e82, dark: 0x8b8b9e)
    static let accent = dyn(light: 0xe5252f, dark: 0xff3b3b)
    static let green = dyn(light: 0x059669, dark: 0x10b981)
    static let gold = dyn(light: 0xca8a04, dark: 0xeab308)
    static let blue = dyn(light: 0x2563eb, dark: 0x3b82f6)
    static let purple = dyn(light: 0x9333ea, dark: 0xa855f7)
    static let orange = dyn(light: 0xea580c, dark: 0xf97316)

    static var accentDim: Color { accent.opacity(0.16) }
    static var greenDim: Color { green.opacity(0.13) }
    static var goldDim: Color { gold.opacity(0.13) }
    static var blueDim: Color { blue.opacity(0.13) }
    static var orangeDim: Color { orange.opacity(0.13) }

    private static func dyn(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .light ? UIColor(hex: light) : UIColor(hex: dark) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}

extension View {
    /// Rounded card surface used across feed rows, lists and panels.
    func card(radius: CGFloat = 14, fill: Color = W.card, stroke: Color = W.border, padding: CGFloat = 12) -> some View {
        self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(stroke, lineWidth: 1))
    }
}
