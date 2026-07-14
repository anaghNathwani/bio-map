import SwiftUI

/// Screen-size categories for layout decisions.
enum ScreenSize {
    case compact   // iPhone SE, iPhone mini
    case regular   // iPhone 14/15, Pro
    case large     // iPhone Plus, Pro Max

    static var current: ScreenSize {
        let h = UIScreen.main.nativeBounds.height / UIScreen.main.nativeScale
        if h < 736 { return .compact }
        if h < 900 { return .regular }
        return .large
    }

    /// Scale a base value by screen size.
    func scale(_ base: CGFloat, compact: CGFloat? = nil, large: CGFloat? = nil) -> CGFloat {
        switch self {
        case .compact: return compact ?? base * 0.8
        case .regular: return base
        case .large:   return large ?? base * 1.1
        }
    }
}

extension View {
    /// Proportional height relative to the screen, clamped to a safe range.
    func proportionalHeight(_ fraction: CGFloat, min minH: CGFloat = 0, max maxH: CGFloat = .infinity) -> some View {
        let h = UIScreen.main.nativeBounds.height / UIScreen.main.nativeScale
        return self.frame(height: Swift.max(minH, Swift.min(maxH, h * fraction)))
    }
}
