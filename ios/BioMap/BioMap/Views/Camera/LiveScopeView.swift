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

