import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { trait in
            UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

/// Light values are the desktop style.css tokens. Dark values keep the same teal identity.
enum Theme {
    static let bg = Color(light: 0xE8EDF0, dark: 0x12191D)
    static let surface = Color(light: 0xF7F9FA, dark: 0x1B2429)
    static let ink = Color(light: 0x1C2830, dark: 0xE6EDF0)
    static let muted = Color(light: 0x5C6B75, dark: 0x9AA8B0)
    static let line = Color(light: 0xC6D0D6, dark: 0x2E3A41)
    static let accent = Color(light: 0x1F6F62, dark: 0x4FB3A1)
    static let noneCell = Color(light: 0xDBE3E7, dark: 0x26323A)
    static let missed = Color(light: 0xE6C9C2, dark: 0x5A3A35)
    static let l1 = Color(light: 0xB7D6CD, dark: 0x1F4D45)
    static let l2 = Color(light: 0x7FB8AA, dark: 0x2B7A6C)
    static let l3 = Color(light: 0x3F9181, dark: 0x3FA593)
    static let l4 = Color(light: 0x145A4F, dark: 0x6FD6C2)
    static let notDone = Color(light: 0xC3CCD2, dark: 0x3A4750)
    static let errorRed = Color(light: 0x9B2C1F, dark: 0xE5786A)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x07201B)
}

extension Font {
    static func serif(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static let themeTitleLarge = Font.serif(20)
    static let themeTitleMedium = Font.serif(17)
    static let themeHeadline = Font.serif(30)
}

/// Flat card: surface fill with a 1 pt line border, like the desktop panels.
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.surface)
            .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))
    }
}

struct AccentButtonStyle: ButtonStyle {
    var filled = true
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .foregroundStyle(filled ? Theme.onAccent : (destructive ? Theme.errorRed : Theme.ink))
            .background(filled ? Theme.accent : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(filled ? Color.clear : Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct StatBlock: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Text(value).font(.themeTitleLarge).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
