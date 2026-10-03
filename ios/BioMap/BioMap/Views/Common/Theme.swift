import SwiftUI

/// BioMap's editorial "paper/ink/clay" design system — the same palette, type and hairline-rule
/// language as the marketing site (web/src/tailwind.css) and the brand social assets
/// (docs/social/instagram, docs/campaign). Warm paper background, a serif display face
/// (Fraunces, italic for emphasis) over a plain sans (Geist), hairline rules instead of card
/// shadows, and clay as the one accent color. Light/dark values mirror the site's exactly so the
/// app, the web map and the brand videos all read as one thing.
enum Theme {
    // MARK: - Color

    /// Resolves against the current color scheme, exactly like the site's `:root` / `[data-theme]` split.
    static func paper(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x17140F) : Color(hex: 0xF4F1E9) }
    static func paperDim(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x201C15) : Color(hex: 0xECE7DA) }
    static func ink(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0xECE7DA) : Color(hex: 0x211D16) }
    static func inkSoft(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0xA69C8B) : Color(hex: 0x6B6255) }
    static func clay(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0xE2895A) : Color(hex: 0xC1602E) }
    static func claySoft(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x7A3F1E) : Color(hex: 0xE4A272) }
    static func rule(_ scheme: ColorScheme) -> Color { ink(scheme).opacity(0.14) }

    // MARK: - Type
    // Bundled as static instances of the same variable webfonts used on the site and in the
    // social videos (see project.yml's UIAppFonts and Resources/Fonts); PostScript names from
    // that conversion.

    static func display(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "FrauncesBioMapDisplay-Medium" : "FrauncesBioMap-Regular", size: size)
    }
    static func displayItalic(_ size: CGFloat) -> Font { .custom("FrauncesBioMap-Italic", size: size) }
    static func sans(_ size: CGFloat) -> Font { .custom("GeistBioMap-Regular", size: size) }
    static func sansMedium(_ size: CGFloat) -> Font { .custom("GeistBioMap-Medium", size: size) }
    static func sansSemibold(_ size: CGFloat) -> Font { .custom("GeistBioMap-SemiBold", size: size) }

    /// The small caps-style label used throughout the reels/site ("CITIZEN SCIENCE", "SUGGESTION"...).
    static func eyebrow(_ size: CGFloat = 13) -> Font { sansSemibold(size) }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Environment-resolved convenience (the common case: `Theme.Colors.ink` inside a View)

/// Reads `\.colorScheme` so call sites don't have to thread it through. Use the static `Theme.ink(_:)`
/// etc. functions instead in non-View contexts (e.g. UIKit bridging) where no Environment is available.
struct ThemeColors {
    let scheme: ColorScheme
    var paper: Color { Theme.paper(scheme) }
    var paperDim: Color { Theme.paperDim(scheme) }
    var ink: Color { Theme.ink(scheme) }
    var inkSoft: Color { Theme.inkSoft(scheme) }
    var clay: Color { Theme.clay(scheme) }
    var claySoft: Color { Theme.claySoft(scheme) }
    var rule: Color { Theme.rule(scheme) }
}

// MARK: - Shared building blocks

/// A hairline border in place of a card shadow — the house style everywhere in the reels and on
/// the site (`.frame`/`.rule` in build.py / tailwind.css) instead of Material or drop shadows.
struct HairlineCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = 18
    var corner: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        let c = ThemeColors(scheme: scheme)
        content
            .padding(padding)
            .background(c.paper, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(c.rule, lineWidth: 1.5))
    }
}

/// The pill button used for every primary action in the reels/site: solid ink fill, paper label,
/// no gradients. `prominent: false` gives the hairline-outline secondary style instead.
struct ClayButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    var prominent: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        let c = ThemeColors(scheme: scheme)
        configuration.label
            .font(Theme.sansSemibold(17))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(prominent ? c.paper : c.ink)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(prominent ? c.ink : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(c.ink, lineWidth: prominent ? 0 : 1.6))
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The small clay-colored tracking-heavy label used everywhere in the brand ("CITIZEN SCIENCE",
/// "SUGGESTION", "TRY IT") — build.py's `.eb` class.
struct Eyebrow: View {
    @Environment(\.colorScheme) private var scheme
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.eyebrow())
            .tracking(1.6)
            .foregroundStyle(Theme.clay(scheme))
    }
}

/// A thin full-width rule, in place of a Divider/card border — `.rule`/`border-bottom` on the site.
struct HairlineRule: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { Theme.rule(scheme).frame(height: 1) }
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
