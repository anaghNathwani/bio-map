import SwiftUI

/// BioMap's loading animation: the brand bird melts into a butterfly, a fish, a leaf, a jellyfish and
/// on down to single-celled life (amoeba, bacterium, yeast, paramecium, diatom), then back to the
/// bird, drawn as one flat blue line. Shapes are radius-vs-angle tables shared with the website
/// (web/scripts/gen_organisms.py -> OrganismData.swift), so morphing is just interpolating radii.
/// With Reduce Motion on it shows the still bird.
struct BioLoader: View {
    var size: CGFloat = 120
    var showsName = true

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let holdSeconds = 1.1
    private let morphSeconds = 0.95
    private let nucleusFrom = 5   // Amoeba onward are microbes and get a nucleus

    var body: some View {
        let c = ThemeColors(scheme: scheme)
        Group {
            if reduceMotion {
                content(radii: OrganismData.all[0].r, nucleus: 0, name: OrganismData.all[0].name, c: c)
            } else {
                TimelineView(.animation) { timeline in
                    let f = frame(at: timeline.date.timeIntervalSinceReferenceDate)
                    content(radii: f.radii, nucleus: f.nucleus, name: f.name, c: c)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }

    private func content(radii: [Double], nucleus: Double, name: String, c: ThemeColors) -> some View {
        VStack(spacing: 14) {
            Canvas { ctx, canvasSize in
                let line = StrokeStyle(lineWidth: max(2, size * 0.018), lineCap: .round, lineJoin: .round)
                ctx.stroke(Self.contour(radii, in: canvasSize), with: .color(c.accent), style: line)
                if nucleus > 0.01 {
                    let r = size * 0.05
                    let dot = CGRect(x: canvasSize.width / 2 - r, y: canvasSize.height / 2 - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: dot), with: .color(c.accent.opacity(nucleus)))
                }
            }
            .frame(width: size, height: size)
            if showsName {
                Text(name)
                    .font(Theme.sansSemibold(15))
                    .foregroundStyle(c.fgSoft)
                    .frame(height: 20)
            }
        }
    }

    private func frame(at time: TimeInterval) -> (radii: [Double], nucleus: Double, name: String) {
        let all = OrganismData.all
        let cycle = holdSeconds + morphSeconds
        let step = Int(time / cycle)
        let within = time - Double(step) * cycle
        let fromIdx = step % all.count
        let toIdx = (step + 1) % all.count
        let raw = within < holdSeconds ? 0 : (within - holdSeconds) / morphSeconds
        let t = raw < 0.5 ? 4 * raw * raw * raw : 1 - pow(-2 * raw + 2, 3) / 2   // ease in-out cubic
        let from = all[fromIdx].r, to = all[toIdx].r
        let radii = zip(from, to).map { $0 + ($1 - $0) * t }
        let a = fromIdx >= nucleusFrom ? 1.0 : 0.0
        let b = toIdx >= nucleusFrom ? 1.0 : 0.0
        return (radii, a + (b - a) * t, all[t > 0.5 ? toIdx : fromIdx].name)
    }

    /// Closed Catmull-Rom spline through the sampled contour.
    static func contour(_ radii: [Double], in size: CGSize) -> Path {
        let n = radii.count
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let scale = min(size.width, size.height) * 0.42
        let pts: [CGPoint] = (0..<n).map { i in
            let a = 2 * Double.pi * Double(i) / Double(n)
            return CGPoint(x: center.x + radii[i] * scale * cos(a), y: center.y - radii[i] * scale * sin(a))
        }
        var path = Path()
        path.move(to: pts[0])
        for i in 0..<n {
            let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.closeSubpath()
        return path
    }
}

#Preview { BioLoader().padding() }
