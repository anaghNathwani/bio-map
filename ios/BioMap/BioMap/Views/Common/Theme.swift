import SwiftUI

/// BioMap's design system: the iOS system look. San Francisco type, system backgrounds and label
/// colors (so light/dark and accessibility settings just work), one blue accent, and quiet grouped
/// surfaces instead of borders or shadows. The website follows the same language (web/src/tailwind.css).
enum Theme {
    // MARK: - Color

    static func bg(_ scheme: ColorScheme) -> Color { Color(.systemBackground) }
    static func bgRaised(_ scheme: ColorScheme) -> Color { Color(.secondarySystemBackground) }
    static func fg(_ scheme: ColorScheme) -> Color { Color(.label) }
    static func fgSoft(_ scheme: ColorScheme) -> Color { Color(.secondaryLabel) }
    /// Apple blue: #0071E3 on light, #0A84FF on dark.
    static func accent(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x0A84FF) : Color(hex: 0x0071E3) }
    static func accentSoft(_ scheme: ColorScheme) -> Color { accent(scheme).opacity(0.14) }
    static func rule(_ scheme: ColorScheme) -> Color { Color(.separator) }

    // MARK: - Type (system font; names kept so call sites read the same)

    static func display(_ size: CGFloat, medium: Bool = false) -> Font {
        .system(size: size, weight: medium ? .semibold : .regular)
    }
    static func displayItalic(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
    static func sans(_ size: CGFloat) -> Font { .system(size: size, weight: .regular) }
    static func sansMedium(_ size: CGFloat) -> Font { .system(size: size, weight: .medium) }
    static func sansSemibold(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }

    /// Small secondary label above a heading ("Citizen science", "Suggestion").
    static func eyebrow(_ size: CGFloat = 13) -> Font { sansSemibold(size) }
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

// MARK: - Environment-resolved convenience

/// Reads `\.colorScheme` so call sites don't have to thread it through.
struct ThemeColors {
    let scheme: ColorScheme
    var bg: Color { Theme.bg(scheme) }
    var bgRaised: Color { Theme.bgRaised(scheme) }
    var fg: Color { Theme.fg(scheme) }
    var fgSoft: Color { Theme.fgSoft(scheme) }
    var accent: Color { Theme.accent(scheme) }
    var accentSoft: Color { Theme.accentSoft(scheme) }
    var rule: Color { Theme.rule(scheme) }
}

// MARK: - Shared building blocks

/// A rounded, softly tinted surface (no border, no shadow), like the tiles on apple.com.
struct Tile<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = 18
    var corner: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        let c = ThemeColors(scheme: scheme)
        content
            .padding(padding)
            .background(c.bgRaised, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

/// The pill button used for every primary action: solid blue capsule, white label.
/// `prominent: false` gives the quiet secondary style (blue text on a pale blue capsule).
struct PillButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    var prominent: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        let c = ThemeColors(scheme: scheme)
        configuration.label
            .font(Theme.sansSemibold(17))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(prominent ? Color.white : c.accent)
            .background(prominent ? c.accent : c.accentSoft, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Small secondary-colored label above a heading.
struct Eyebrow: View {
    @Environment(\.colorScheme) private var scheme
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.eyebrow())
            .foregroundStyle(Theme.fgSoft(scheme))
    }
}

/// A thin full-width separator.
struct HairlineRule: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { Theme.rule(scheme).frame(height: 1 / UIScreen.main.scale) }
}

/// The brand mark: the line-art bird from build.py's `bird()` / the campaign's logo path, drawn as
/// a real vector (not a bundled image) so it inherits the current ink/clay color like everywhere else.
struct BirdMark: Shape {
    func path(in rect: CGRect) -> Path {
        // Same path data as BIRD_PATH in docs/social/instagram/build.py and docs/campaign/build_campaign.py,
        // on a 48x48 canvas.
        var p = Path()
        let s = rect.width / 48
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        p.move(to: pt(6, 27))
        p.addCurve(to: pt(34, 7), control1: pt(11, 14), control2: pt(21, 7))
        p.addCurve(to: pt(41, 8.1), control1: pt(36.7, 7), control2: pt(39, 7.4))
        p.addCurve(to: pt(36.6, 12.1), control1: pt(39.2, 9.1), control2: pt(37.7, 10.4))
        p.addCurve(to: pt(45, 15.3), control1: pt(40, 12.4), control2: pt(43, 13.4))
        p.addCurve(to: pt(37.3, 18.5), control1: pt(42, 15.6), control2: pt(39.4, 16.7))
        p.addCurve(to: pt(30.9, 36.1), control1: pt(38.3, 25.2), control2: pt(36.1, 31.5))
        p.addCurve(to: pt(11, 42.4), control1: pt(25.8, 41.4), control2: pt(18.8, 43.6))
        p.addCurve(to: pt(19.8, 36.9), control1: pt(14.6, 41.4), control2: pt(17.6, 39.5))
        p.addCurve(to: pt(7.6, 29.8), control1: pt(14.8, 36.5), control2: pt(10.4, 33.9))
        p.addCurve(to: pt(15, 29.4), control1: pt(10.2, 30.5), control2: pt(12.7, 30.4))
        p.addCurve(to: pt(6, 21.2), control1: pt(11, 27.8), control2: pt(7.9, 25))
        p.closeSubpath()
        return p
    }
}
