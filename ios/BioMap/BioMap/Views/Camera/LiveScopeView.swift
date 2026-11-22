import SwiftUI
import AVFoundation

/// Incognito live view: the camera with a green, pixelated, terminal-style box and tag on every bird. Tap a bird to
/// pick it out. Nothing is recorded, saved or uploaded.
struct LiveScopeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var scope = LiveBirdScope()

    private static let green = Color(red: 0, green: 1, blue: 0.255)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if scope.status == .running || scope.status == .starting {
                CameraPreview(session: scope.session).ignoresSafeArea()
            }
            GeometryReader { geo in
                let map = FrameMap(frame: scope.frameSize, view: geo.size)
                TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: reduceMotion)) { timeline in
                    Canvas { ctx, _ in
                        let tick = Int(timeline.date.timeIntervalSinceReferenceDate * 8)
                        for bird in scope.birds {
                            PixelBox.draw(in: &ctx, rect: map.rect(bird.box), selected: bird.id == scope.selectedID,
                                          tick: reduceMotion ? 0 : tick, animated: !reduceMotion, color: Self.green)
                        }
                    }
                }
                .allowsHitTesting(false)

                ForEach(scope.birds) { bird in
                    let r = map.rect(bird.box)
                    let selected = bird.id == scope.selectedID
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                        .onTapGesture { scope.selectedID = selected ? nil : bird.id }
                        .accessibilityElement()
                        .accessibilityLabel(bird.species.map { "Bird: \($0)" } ?? "Bird, identifying")
                        .accessibilityAddTraits(.isButton)
                    tag(for: bird, rect: r, selected: selected, in: geo.size)
                }
            }
            .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                bottomBar
            }
            if scope.status == .denied || scope.status == .unavailable { problem }
        }
        .statusBarHidden()
        .onAppear { scope.start(); UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { scope.stop(); UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: - Pieces

    private func tag(for bird: LiveBird, rect: CGRect, selected: Bool, in size: CGSize) -> some View {
        let name = bird.species?.uppercased() ?? "SCANNING…"
        let text = selected && bird.species != nil ? "> \(name)  \(Int(bird.confidence * 100))%" : "> \(name)"
        return Text(text)
            .font(.system(size: selected ? 13 : 11, weight: .bold, design: .monospaced))
            .foregroundStyle(Self.green)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.black.opacity(0.82))
            .overlay(Rectangle().strokeBorder(Self.green.opacity(selected ? 1 : 0.6), lineWidth: 1))
            .fixedSize()
            .position(x: min(max(rect.minX + 4, 0) + 70, size.width - 70), y: rect.minY > 40 ? rect.minY - 14 : rect.minY + 16)
            .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 6) {
                Rectangle().fill(Self.green).frame(width: 8, height: 8)
                Text("LIVE  ·  INCOGNITO").font(.system(size: 12, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(Self.green)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.black.opacity(0.7))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Self.green)
                    .frame(width: 34, height: 34).background(Color.black.opacity(0.7))
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 4) {
            Text(scope.birds.isEmpty ? "NO BIRDS IN VIEW" : "\(scope.birds.count) BIRD\(scope.birds.count == 1 ? "" : "S") IN VIEW  ·  TAP ONE")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
            Text("Nothing is recorded, saved or uploaded.")
                .font(.system(size: 11, design: .monospaced)).opacity(0.75)
        }
        .foregroundStyle(Self.green)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.black.opacity(0.7))
        .padding(.bottom, 24)
    }

    private var problem: some View {
        VStack(spacing: 10) {
            Text(scope.status == .denied ? "CAMERA ACCESS IS OFF" : "LIVE VIEW NEEDS A CAMERA")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
            Text(scope.status == .denied ? "Turn it on in Settings > BioMap." : "This device has no camera available.")
                .font(.system(size: 12, design: .monospaced))
        }
        .foregroundStyle(Self.green).multilineTextAlignment(.center).padding(24)
    }
}

/// Maps a normalised box in the camera frame to view coordinates when the preview fills the screen (aspect fill).
struct FrameMap {
    let frame: CGSize, view: CGSize
    func rect(_ n: CGRect) -> CGRect {
        let scale = max(view.width / frame.width, view.height / frame.height)
        let dx = (view.width - frame.width * scale) / 2, dy = (view.height - frame.height * scale) / 2
        return CGRect(x: dx + n.minX * frame.width * scale, y: dy + n.minY * frame.height * scale,
                      width: n.width * frame.width * scale, height: n.height * frame.height * scale)
    }
}

/// The green, blocky box: an outline and corner brackets made of square "pixels", a sparse flickering dither inside and a
/// scan line that sweeps down it.
enum PixelBox {
    static let cell: CGFloat = 5

    static func draw(in ctx: inout GraphicsContext, rect: CGRect, selected: Bool, tick: Int, animated: Bool, color: Color) {
        let cols = max(Int(rect.width / cell), 4), rows = max(Int(rect.height / cell), 4)
        let origin = CGPoint(x: (rect.minX / cell).rounded() * cell, y: (rect.minY / cell).rounded() * cell)
        func cellRect(_ c: Int, _ r: Int) -> CGRect {
            CGRect(x: origin.x + CGFloat(c) * cell + 0.5, y: origin.y + CGFloat(r) * cell + 0.5, width: cell - 1, height: cell - 1)
        }

        var dither = Path(), outline = Path(), brackets = Path(), scan = Path()
        let density = selected ? 5 : 11                        // one cell in `density` lights up
        let sweep = animated ? (tick % (rows + 8)) - 4 : -10
        for r in 0..<rows {
            for c in 0..<cols {
                let edge = r == 0 || r == rows - 1 || c == 0 || c == cols - 1
                let corner = (r < 3 || r >= rows - 3) && (c < 3 || c >= cols - 3)
                if corner, edge || r < 2 || r >= rows - 2 || c < 2 || c >= cols - 2 { brackets.addRect(cellRect(c, r)); continue }
                if edge { if (c + r) % 2 == 0 || selected { outline.addRect(cellRect(c, r)) }; continue }
                if r == sweep { scan.addRect(cellRect(c, r)); continue }
                var h = UInt64(c &* 73856093) ^ UInt64(r &* 19349663) ^ UInt64(tick &* 83492791)
                h = (h ^ (h >> 13)) &* 0x5bd1e995
                if Int(h % UInt64(density)) == 0 { dither.addRect(cellRect(c, r)) }
            }
        }
        ctx.fill(dither, with: .color(color.opacity(selected ? 0.35 : 0.22)))
        ctx.fill(scan, with: .color(color.opacity(0.4)))
        ctx.fill(outline, with: .color(color.opacity(selected ? 0.95 : 0.7)))
        ctx.fill(brackets, with: .color(color))
    }
}

