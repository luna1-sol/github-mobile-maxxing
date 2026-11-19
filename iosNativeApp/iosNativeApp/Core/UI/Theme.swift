import SwiftUI

extension Color {
    /// `RRGGBB` / `#RRGGBB` (GitHub label and language colours). Falls back to gray for malformed input.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        let value = UInt32(cleaned.prefix(6), radix: 16) ?? 0x8C959F
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// Whether black text reads better than white on a background of this hex colour.
    static func prefersDarkText(onHex hex: String) -> Bool {
        let value = UInt32(hex.replacingOccurrences(of: "#", with: "").prefix(6), radix: 16) ?? 0
        let r = Double((value >> 16) & 0xFF), g = Double((value >> 8) & 0xFF), b = Double(value & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.6
    }

    /// Content colour on an accent fill (Material 3 "onPrimary"): white on the light-mode purple, dark purple on the
    /// light lavender dark-mode accent, where the system's white label of `.glassProminent` is hard to read.
    static let onAccent = Color("OnAccentColor")
}

extension View {
    /// Label colour for an accent-filled `.glassProminent` button; pass `false` when the button is currently `.glass`.
    func onAccentLabel(_ prominent: Bool = true) -> some View {
        foregroundStyle(prominent ? AnyShapeStyle(Color.onAccent) : AnyShapeStyle(.primary))
    }
}

/// GitHub-style semantic colours for states.
enum StateColors {
    static let open = Color(hex: "1A7F37")
    static let closed = Color(hex: "CF222E")
    static let merged = Color(hex: "8250DF")
    static let draft = Color(hex: "6E7781")
    static let added = Color(hex: "1A7F37")
    static let removed = Color(hex: "CF222E")
}

// MARK: - Liquid Glass helpers

extension View {
    /// A floating Liquid Glass capsule for controls that sit above content (filters, action bars, composer).
    func glassCapsule(tint: Color? = nil, interactive: Bool = true) -> some View {
        glassEffect(glass(tint: tint, interactive: interactive), in: .capsule)
    }

    /// A rounded Liquid Glass panel for small overlays (code/badge panels, sign-in card).
    func glassPanel(cornerRadius: CGFloat = 24, tint: Color? = nil, interactive: Bool = false) -> some View {
        glassEffect(glass(tint: tint, interactive: interactive), in: .rect(cornerRadius: cornerRadius))
    }

    /// Solid grouped background for content cards. Content stays off the glass layer, as Apple's
    /// Liquid Glass guidance reserves glass for navigation and controls.
    func contentCard(cornerRadius: CGFloat = 20) -> some View {
        background(.background.secondary, in: .rect(cornerRadius: cornerRadius))
    }
}

private func glass(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}
