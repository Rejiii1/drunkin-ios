import SwiftUI

enum Theme {
    static let night = Color(hex: 0x071E36)
    static let card = Color(hex: 0x0D2C4D)
    static let card2 = Color(hex: 0x123A63)
    static let line = Color(hex: 0x23507E)
    static let cream = Color(hex: 0xF6EBD5)
    static let muted = Color(hex: 0xA9BCD0)
    static let gold = Color(hex: 0xF5C518)
    static let amber = Color(hex: 0xE39B2D)
    static let moss = Color(hex: 0x7CC08A)
    static let water = Color(hex: 0x7FC8F8)
    static let alert = Color(hex: 0xF28B82)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Font {
    static func display(_ style: Font.TextStyle) -> Font { .system(style, design: .serif).weight(.bold) }
    static func numeral(_ style: Font.TextStyle) -> Font { .system(style, design: .rounded).weight(.heavy) }
}

struct CardModifier: ViewModifier {
    var highlighted = false
    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(highlighted ? Theme.gold : Theme.line, lineWidth: highlighted ? 1.5 : 1)
            )
    }
}

extension View {
    func card(highlighted: Bool = false) -> some View { modifier(CardModifier(highlighted: highlighted)) }

    func screen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.night.ignoresSafeArea())
            .toolbarBackground(Theme.night, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

struct Eyebrow: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.6)
            .foregroundStyle(Theme.amber)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 16)
            .foregroundStyle(Theme.night)
            .background(Theme.gold.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct GhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 16)
            .foregroundStyle(Theme.cream)
            .background(Theme.card2.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line))
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == GhostButtonStyle {
    static var ghost: GhostButtonStyle { GhostButtonStyle() }
}

struct Logo: View {
    var size: CGFloat = 120
    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityLabel("Drunkin")
    }
}

struct AvatarView: View {
    var name: String
    var data: Data?
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let data, let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.night)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(color)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap(\.first).map(String.init).joined()
        return s.isEmpty ? "?" : s.uppercased()
    }

    private var color: Color {
        let palette: [Color] = [Theme.gold, Theme.amber, Theme.moss, Theme.water, Color(hex: 0xC9A7EB), Color(hex: 0xF4A3A8)]
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[abs(sum) % palette.count]
    }
}

extension Tasting {
    func avatar(_ id: UUID?, size: CGFloat = 32) -> AvatarView {
        AvatarView(name: name(of: id), data: id.flatMap { avatars[$0] }, size: size)
    }
}
