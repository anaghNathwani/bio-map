import UIKit

/// Zoom maths for the in-app camera, kept free of AVFoundation so it can be tested without a camera.
///
/// The native Camera app calls the main (wide) lens "1×". On phones with an ultra-wide lens the virtual
/// camera's raw `videoZoomFactor` of 1.0 is the ultra-wide, so the wide lens sits at the first
/// switch-over factor (typically 2.0) and the display value is `raw / base`.
enum CameraZoom {
    /// Largest zoom (in display units) we allow; beyond this a phone photo is too soft to identify a bird.
    static let maxDisplayZoom: CGFloat = 15

    static func base(hasUltraWide: Bool, switchOver: [CGFloat]) -> CGFloat {
        hasUltraWide ? (switchOver.first ?? 1) : 1
    }

    /// The preset stops shown in the zoom bar, in display units: ultra-wide (0.5), wide (1), any
    /// telephoto lens (e.g. 3 or 5), plus a 2× sensor crop when no lens already sits there.
    static func presets(hasUltraWide: Bool, switchOver: [CGFloat], maxDisplay: CGFloat = maxDisplayZoom) -> [CGFloat] {
        let b = base(hasUltraWide: hasUltraWide, switchOver: switchOver)
        var stops: [CGFloat] = []
        if hasUltraWide { stops.append(1 / b) }
        stops.append(1)
        stops += (hasUltraWide ? Array(switchOver.dropFirst()) : switchOver).map { $0 / b }
        if !stops.contains(where: { abs($0 - 2) < 0.05 }) { stops.append(2) }
        let rounded = Set(stops.map { ($0 * 10).rounded() / 10 })
        return rounded.filter { $0 <= maxDisplay + 0.01 }.sorted()
    }

    /// The preset that's "current": the largest stop not above the zoom, like the native bar.
    static func activeIndex(presets: [CGFloat], current: CGFloat) -> Int {
        presets.lastIndex(where: { $0 <= current + 0.02 }) ?? 0
    }

    /// ".5", "1", "2" for inactive stops; "1×", "3.4×" for the active one, as the native bar shows.
    static func label(_ value: CGFloat, active: Bool) -> String {
        let r = (value * 10).rounded() / 10
        var s = r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
        if s.hasPrefix("0.") { s.removeFirst() }
        return active ? s + "×" : s
    }
}

/// The row of round zoom buttons above the shutter. The active one turns yellow and shows the exact zoom.
final class ZoomBar: UIView {
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let stack = UIStackView()
    private var buttons: [UIButton] = []
    private var widths: [NSLayoutConstraint] = []
    private(set) var presets: [CGFloat] = []
    private var lastActive = -1
    private let haptic = UISelectionFeedbackGenerator()

    /// Set while the user is pinching, so crossing a lens fires a tick but a tapped ramp doesn't fire several.
    var hapticsEnabled = false
    var onSelect: ((CGFloat) -> Void)?

    private static let yellow = UIColor(red: 1, green: 0.84, blue: 0.04, alpha: 1)   // the native Camera's yellow

    override init(frame: CGRect) {
        super.init(frame: frame)
        blur.isUserInteractionEnabled = false
        addSubview(blur)
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        addSubview(stack)
        [blur, stack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor), blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor), blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 5), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
        layer.cornerRadius = 25
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(presets: [CGFloat]) {
        self.presets = presets
        buttons.forEach { $0.removeFromSuperview() }
        buttons = []; widths = []; lastActive = -1
        for (i, p) in presets.enumerated() {
            let b = UIButton(type: .custom)
            b.tag = i
            b.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.titleLabel?.minimumScaleFactor = 0.7
            b.layer.cornerRadius = 18
            b.accessibilityLabel = "\(CameraZoom.label(p, active: false)) times zoom"
            b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            let w = b.widthAnchor.constraint(equalToConstant: 36)
            w.isActive = true
            b.heightAnchor.constraint(equalToConstant: 36).isActive = true
            stack.addArrangedSubview(b)
            buttons.append(b); widths.append(w)
        }
        update(current: presets.first(where: { $0 >= 1 }) ?? 1)
    }

    @objc private func tapped(_ b: UIButton) { onSelect?(presets[b.tag]) }

    /// Refresh labels for the current zoom (display units).
    func update(current: CGFloat) {
        guard !presets.isEmpty else { return }
        let active = CameraZoom.activeIndex(presets: presets, current: current)
        if active != lastActive, lastActive != -1, hapticsEnabled { haptic.selectionChanged() }
        let changed = active != lastActive
        lastActive = active
        for (i, b) in buttons.enumerated() {
            let isActive = i == active
            b.setTitle(CameraZoom.label(isActive ? current : presets[i], active: isActive), for: .normal)
            b.setTitleColor(isActive ? Self.yellow : .white, for: .normal)
            b.backgroundColor = isActive ? UIColor.black.withAlphaComponent(0.45) : .clear
            widths[i].constant = isActive ? 42 : 36
        }
        if changed { UIView.animate(withDuration: 0.2) { self.layoutIfNeeded() } }
        else { layoutIfNeeded() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

/// The native-style shutter: a white ring around a white disc that squeezes when pressed.
final class ShutterButton: UIControl {
    private let ring = CAShapeLayer()
    private let disc = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = UIColor.white.cgColor
        ring.lineWidth = 4
        layer.addSublayer(ring)
        disc.backgroundColor = .white
        disc.isUserInteractionEnabled = false
        addSubview(disc)
        isAccessibilityElement = true
        accessibilityLabel = "Take photo"
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { UIView.animate(withDuration: 0.1) { self.disc.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.88, y: 0.88) : .identity } }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ring.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2)).cgPath
        disc.frame = bounds.insetBy(dx: 8, dy: 8)
        disc.layer.cornerRadius = disc.bounds.width / 2
    }
}

/// The yellow square that appears where you tap to focus.
final class FocusSquare: UIView {
    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 76, height: 76))
        layer.borderColor = UIColor(red: 1, green: 0.84, blue: 0.04, alpha: 1).cgColor
        layer.borderWidth = 1.5
        isUserInteractionEnabled = false
        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(at point: CGPoint) {
        layer.removeAllAnimations()
        center = point
        transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
        alpha = 1
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) { self.transform = .identity }
        UIView.animate(withDuration: 0.3, delay: 1.0, options: []) { self.alpha = 0 }
    }
}
