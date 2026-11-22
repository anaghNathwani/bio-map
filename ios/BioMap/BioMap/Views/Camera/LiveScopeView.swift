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

